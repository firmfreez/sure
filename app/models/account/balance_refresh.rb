class Account::BalanceRefresh
  def self.call(accounts)
    accounts = Array(accounts).compact.uniq(&:id).sort_by(&:id)

    Account.transaction do
      # Lock in a stable order and publish both sides of a transfer together.
      accounts.each(&:lock!)
      accounts.each do |account|
        Balance::Materializer.new(account, strategy: account.linked? ? :reverse : :forward, strict_fx: true).materialize_balances
        account.touch
      end
    end

    accounts.each(&:broadcast_refresh)
  rescue Money::ConversionError => error
    # The entry is already saved and its normal background sync will retry.
    # Keep the previous balances together when historical FX data is missing.
    DebugLogEntry.capture(
      category: "balance_refresh", level: "warn", source: name,
      message: "Immediate balance refresh deferred because an exchange rate is unavailable",
      family: accounts.first&.family,
      provider_key: ENV["EXCHANGE_RATE_PROVIDER"].presence || Setting.exchange_rate_provider,
      metadata: { account_ids: accounts.map(&:id), from_currency: error.from_currency,
                  to_currency: error.to_currency, date: error.date }
    )
    false
  end
end
