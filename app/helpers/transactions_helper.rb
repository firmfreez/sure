module TransactionsHelper
  def transaction_display_name(entry)
    return entry.name unless entry.entryable.transfer?

    transfer = entry.entryable.transfer
    return entry.name unless transfer

    %w[to from].each do |direction|
      { "Transfer" => "name", "Payment" => "payment_name" }.each do |prefix, key|
        next unless entry.name.start_with?("#{prefix} #{direction} ")

        account = direction == "to" ? transfer.to_account : transfer.from_account
        next unless account
        next unless entry.name == "#{prefix} #{direction} #{account.name}"

        translation_key = direction == "from" ? "#{key}_from" : key
        return t("transfer.#{translation_key}", to_account: account.name, from_account: account.name)
      end
    end

    entry.name
  end

  def transaction_category_filter_checked?(category, query)
    if query[:category_ids].present?
      value = category.id.presence || Category::UNCATEGORIZED_FILTER_TOKEN
      query[:category_ids].include?(value)
    elsif category.persisted?
      Array(query[:categories]).include?(category.name)
    else
      (Array(query[:categories]) & Category.all_uncategorized_names).any?
    end
  end

  def transaction_search_filters
    [
      { key: "account_filter", label: t("transactions.search.filters.account"), icon: "layers" },
      { key: "date_filter", label: t("transactions.search.filters.date"), icon: "calendar" },
      { key: "type_filter", label: t("transactions.search.filters.type"), icon: "tag" },
      { key: "status_filter", label: t("transactions.search.filters.status"), icon: "clock" },
      { key: "amount_filter", label: t("transactions.search.filters.amount"), icon: "hash" },
      { key: "category_filter", label: t("transactions.search.filters.category"), icon: "shapes" },
      { key: "tag_filter", label: t("transactions.search.filters.tag"), icon: "tags" },
      { key: "merchant_filter", label: t("transactions.search.filters.merchant"), icon: "store" }
    ]
  end

  def get_transaction_search_filter_partial_path(filter)
    "transactions/searches/filters/#{filter[:key]}"
  end

  def get_default_transaction_search_filter
    transaction_search_filters[0]
  end

  def in_split_group?(entry, params_grouped)
    entry.split_child? && Current.user.show_split_grouped? && params_grouped == "true"
  end

  # ---- Transaction extra details helpers ----
  # Returns a structured hash describing extra details for a transaction.
  # Input can be a Transaction or an Entry (responds_to :transaction).
  # Structure:
  #   {
  #     kind: :simplefin | :raw,
  #     simplefin: { payee:, description:, memo: },
  #     provider_extras: [ { key:, value:, title: } ],
  #     raw: String (pretty JSON or string)
  #   }
  def build_transaction_extra_details(obj)
    tx = obj.respond_to?(:transaction) ? obj.transaction : obj
    return nil unless tx.respond_to?(:extra) && tx.extra.present?

    extra = tx.extra

    if extra.is_a?(Hash) && extra["simplefin"].present?
      sf = extra["simplefin"]
      simple = {
        payee: sf.is_a?(Hash) ? sf["payee"].presence : nil,
        description: sf.is_a?(Hash) ? sf["description"].presence : nil,
        memo: sf.is_a?(Hash) ? sf["memo"].presence : nil
      }.compact

      extras = []
      if sf.is_a?(Hash) && sf["extra"].is_a?(Hash) && sf["extra"].present?
        sf["extra"].each do |k, v|
          display = (v.is_a?(Hash) || v.is_a?(Array)) ? v.to_json : v
          extras << {
            key: k.to_s.humanize,
            value: display,
            title: (v.is_a?(String) ? v : display.to_s)
          }
        end
      end

      {
        kind: :simplefin,
        simplefin: simple,
        provider_extras: extras,
        raw: nil
      }
    else
      pretty = begin
        JSON.pretty_generate(extra)
      rescue StandardError
        extra.to_s
      end
      {
        kind: :raw,
        simplefin: {},
        provider_extras: [],
        raw: pretty
      }
    end
  end
end
