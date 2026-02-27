class Transaction::Search
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :search, :string
  attribute :amount, :string
  attribute :amount_operator, :string
  attribute :types, array: true
  attribute :status, array: true
  attribute :accounts, array: true
  attribute :account_ids, array: true
  attribute :start_date, :string
  attribute :end_date, :string
  attribute :category_ids, array: true
  attribute :merchants, array: true
  attribute :tags, array: true
  attribute :active_accounts_only, :boolean, default: true

  attr_reader :family

  def initialize(family, filters: {})
    @family = family
    super(filters)
  end

  def transactions_scope
    @transactions_scope ||= begin
      # This already joins entries + accounts. To avoid expensive double-joins, don't join them again (causes full table scan)
      query = family.transactions

      query = apply_active_accounts_filter(query, active_accounts_only)
      query = apply_category_filter(query, category_ids)
      query = apply_type_filter(query, types)
      query = apply_status_filter(query, status)
      query = apply_merchant_filter(query, merchants)
      query = apply_tag_filter(query, tags)
      query = EntrySearch.apply_search_filter(query, search)
      query = EntrySearch.apply_date_filters(query, start_date, end_date)
      query = EntrySearch.apply_amount_filter(query, amount, amount_operator)
      query = EntrySearch.apply_accounts_filter(query, accounts, account_ids)

      query
    end
  end

  # Computes totals for the specific search
  # Note: Excludes tax-advantaged accounts (401k, IRA, etc.) from totals calculation
  # because those transactions are retirement savings, not daily income/expenses.
  def totals
    @totals ||= begin
      Rails.cache.fetch("transaction_search_totals/#{cache_key_base}") do
        scope = transactions_scope

        # Exclude tax-advantaged accounts from totals calculation
        tax_advantaged_ids = family.tax_advantaged_account_ids
        scope = scope.where.not(accounts: { id: tax_advantaged_ids }) if tax_advantaged_ids.present?

        result = scope
                  .select(
                    ActiveRecord::Base.sanitize_sql_array([
                      "COALESCE(SUM(CASE WHEN entries.amount >= 0 AND transactions.kind NOT IN (?) THEN ABS(entries.amount * COALESCE(er.rate, 1)) ELSE 0 END), 0) as expense_total",
                      Transaction::TRANSFER_KINDS
                    ]),
                    ActiveRecord::Base.sanitize_sql_array([
                      "COALESCE(SUM(CASE WHEN entries.amount < 0 AND transactions.kind NOT IN (?) THEN ABS(entries.amount * COALESCE(er.rate, 1)) ELSE 0 END), 0) as income_total",
                      Transaction::TRANSFER_KINDS
                    ]),
                    "COUNT(entries.id) as transactions_count"
                  )
                  .joins(
                    ActiveRecord::Base.sanitize_sql_array([
                      "LEFT JOIN exchange_rates er ON (er.date = entries.date AND er.from_currency = entries.currency AND er.to_currency = ?)",
                      family.currency
                    ])
                  )
                  .take
        result ||= Struct.new(:expense_total, :income_total, :transactions_count).new(0, 0, 0)

        Totals.new(
          count: result.transactions_count.to_i,
          income_money: Money.new(result.income_total, family.currency),
          expense_money: Money.new(result.expense_total, family.currency)
        )
      end
    end
  end

  def cache_key_base
    [
      family.id,
      Digest::SHA256.hexdigest(attributes.sort.to_h.to_json), # cached by filters
      family.entries_cache_version,
      Digest::SHA256.hexdigest(family.tax_advantaged_account_ids.sort.to_json) # stable across processes
    ].join("/")
  end

  private
    Totals = Data.define(:count, :income_money, :expense_money)

    def apply_active_accounts_filter(query, active_accounts_only_filter)
      if active_accounts_only_filter
        query.where(accounts: { status: [ "draft", "active" ] })
      else
        query
      end
    end


    def apply_category_filter(query, category_ids)
      category_filter_requested = category_ids.present?
      selected_ids, include_uncategorized = normalized_category_filter(category_ids)
      return category_filter_requested ? query.none : query if selected_ids.blank? && !include_uncategorized

      expanded_ids = selected_ids + family.categories.where(parent_id: selected_ids).pluck(:id)
      expanded_ids = expanded_ids.uniq

      if include_uncategorized
        if expanded_ids.present?
          query.left_joins(:category).where(
            "categories.id IN (?) OR (categories.id IS NULL AND transactions.kind NOT IN (?))",
            expanded_ids, Transaction::TRANSFER_KINDS
          )
        else
          query.left_joins(:category).where(
            "categories.id IS NULL AND transactions.kind NOT IN (?)",
            Transaction::TRANSFER_KINDS
          )
        end
      else
        query.where(category_id: expanded_ids)
      end
    end

    def normalized_category_filter(category_ids)
      ids = Array(category_ids).map(&:to_s).reject(&:blank?)
      include_uncategorized = ids.delete(Category::UNCATEGORIZED_FILTER_TOKEN).present?

      [ ids.uniq, include_uncategorized ]
    end

    def apply_type_filter(query, types)
      return query unless types.present?
      return query if types.sort == [ "expense", "income", "transfer" ]

      case types.sort
      when [ "transfer" ]
        query.where(kind: Transaction::TRANSFER_KINDS)
      when [ "expense" ]
        query.where("entries.amount >= 0").where.not(kind: Transaction::TRANSFER_KINDS)
      when [ "income" ]
        query.where("entries.amount < 0").where.not(kind: Transaction::TRANSFER_KINDS)
      when [ "expense", "transfer" ]
        query.where("entries.amount >= 0 OR transactions.kind IN (?)", Transaction::TRANSFER_KINDS)
      when [ "income", "transfer" ]
        query.where("entries.amount < 0 OR transactions.kind IN (?)", Transaction::TRANSFER_KINDS)
      when [ "expense", "income" ]
        query.where.not(kind: Transaction::TRANSFER_KINDS)
      else
        query
      end
    end

    def apply_merchant_filter(query, merchants)
      return query unless merchants.present?
      query.joins(:merchant).where(merchants: { name: merchants })
    end

    def apply_tag_filter(query, tags)
      return query unless tags.present?
      query.joins(:tags).where(tags: { name: tags })
    end

    def apply_status_filter(query, statuses)
      return query unless statuses.present?
      return query if statuses.uniq.sort == [ "confirmed", "pending" ] # Both selected = no filter

      pending_condition = <<~SQL.squish
        (transactions.extra -> 'simplefin' ->> 'pending')::boolean = true
        OR (transactions.extra -> 'plaid' ->> 'pending')::boolean = true
        OR (transactions.extra -> 'lunchflow' ->> 'pending')::boolean = true
      SQL

      confirmed_condition = <<~SQL.squish
        (transactions.extra -> 'simplefin' ->> 'pending')::boolean IS DISTINCT FROM true
        AND (transactions.extra -> 'plaid' ->> 'pending')::boolean IS DISTINCT FROM true
        AND (transactions.extra -> 'lunchflow' ->> 'pending')::boolean IS DISTINCT FROM true
      SQL

      case statuses.sort
      when [ "pending" ]
        query.where(pending_condition)
      when [ "confirmed" ]
        query.where(confirmed_condition)
      else
        query
      end
    end
end
