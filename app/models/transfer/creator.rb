class Transfer::Creator
  def initialize(family:, source_account_id:, destination_account_id:, date:, amount:)
    @family = family
    @source_account = family.accounts.find(source_account_id) # early throw if not found
    @destination_account = family.accounts.find(destination_account_id) # early throw if not found
    @date = date
    @amount = amount.to_d
  end

  def create
    transfer = Transfer.new(
      inflow_transaction: inflow_transaction,
      outflow_transaction: outflow_transaction,
      status: "confirmed"
    )

    if transfer.save
      source_account.sync_later
      destination_account.sync_later
    end

    transfer
  end

  private
    attr_reader :family, :source_account, :destination_account, :date, :amount

    def outflow_transaction
      name = transfer_name_to(destination_account.name)
      kind = outflow_transaction_kind

      Transaction.new(
        kind: kind,
        category: (investment_contributions_category if kind == "investment_contribution"),
        entry: source_account.entries.build(
          amount: amount.abs,
          currency: source_account.currency,
          date: date,
          name: name,
          user_modified: true, # Protect from provider sync claiming this entry
        )
      )
    end

    def investment_contributions_category
      source_account.family.investment_contributions_category
    end

    def inflow_transaction
      name = transfer_name_from(source_account.name)

      Transaction.new(
        kind: "funds_movement",
        entry: destination_account.entries.build(
          amount: inflow_converted_money.amount.abs * -1,
          currency: destination_account.currency,
          date: date,
          name: name,
          user_modified: true, # Protect from provider sync claiming this entry
        )
      )
    end

    # If destination account has different currency, its transaction should show up as converted
    # Future improvement: instead of a 1:1 conversion fallback, add a UI/UX flow for missing rates
    def inflow_converted_money
      Money.new(amount.abs, source_account.currency)
           .exchange_to(
             destination_account.currency,
             date: date,
             fallback_rate: 1.0
           )
    end

    # The "expense" side of a transfer is treated different in analytics based on where it goes.
    def outflow_transaction_kind
      if destination_account.loan?
        "loan_payment"
      elsif destination_account.liability?
        "cc_payment"
      elsif destination_is_investment? && !source_is_investment?
        "investment_contribution"
      else
        "funds_movement"
      end
    end

    def destination_is_investment?
      destination_account.investment? || destination_account.crypto?
    end

    def source_is_investment?
      source_account.investment? || source_account.crypto?
    end

    def name_prefix_key
      destination_account.liability? ? "payment" : "transfer"
    end

    def transfer_name_to(account_name)
      I18n.t("models.transfer.#{name_prefix_key}_to", account: account_name, default: "#{name_prefix} to #{account_name}")
    end

    def transfer_name_from(account_name)
      I18n.t("models.transfer.#{name_prefix_key}_from", account: account_name, default: "#{name_prefix} from #{account_name}")
    end

    def name_prefix
      I18n.t("models.transfer.#{name_prefix_key}", default: name_prefix_key.titleize)
    end
end
