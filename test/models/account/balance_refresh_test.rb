require "test_helper"

class Account::BalanceRefreshTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @source, @destination = [ "Source", "Destination" ].map do |name|
      account = families(:empty).accounts.create!(
        name: name, currency: "USD", balance: 1000, cash_balance: 1000, accountable: Depository.new
      )
      create_valuation(account: account, amount: 1000, date: 2.days.ago.to_date, kind: "opening_anchor")
      account
    end
  end

  test "income and expense update the balance before any sync job runs" do
    create_transaction(account: @source, amount: -200)
    Account::BalanceRefresh.call(@source)
    assert_equal 1200, @source.reload.balance

    create_transaction(account: @source, amount: 50)
    Account::BalanceRefresh.call(@source)
    assert_equal 1150, @source.reload.balance
    assert_equal 1150, @source.cash_balance
  end

  test "both transfer accounts include the transfer and its fee immediately" do
    create_transaction(account: @source, amount: 100)
    create_transaction(account: @destination, amount: -100)
    create_transaction(account: @source, amount: 2)

    Account::BalanceRefresh.call([ @source, @destination ])

    assert_equal 898, @source.reload.balance
    assert_equal 1100, @destination.reload.balance
  end

  test "failure on the second account rolls back the first account balance" do
    first, second = [ @source, @destination ].sort_by(&:id)
    create_transaction(account: first, amount: 100)
    create_transaction(account: second, amount: -100)
    failed_materializer = mock
    failed_materializer.expects(:materialize_balances).raises("Cannot calculate")
    first_materializer = Balance::Materializer.new(first, strategy: :forward, strict_fx: true)
    Balance::Materializer.stubs(:new).with(first, strategy: :forward, strict_fx: true).returns(first_materializer)
    Balance::Materializer.stubs(:new).with(second, strategy: :forward, strict_fx: true).returns(failed_materializer)

    assert_raises(RuntimeError) { Account::BalanceRefresh.call([ first, second ]) }

    assert_equal 1000, first.reload.balance
    assert_equal 1000, second.reload.balance
  end

  test "linked accounts retain the provider balance" do
    @source.stubs(:linked?).returns(true)
    create_transaction(account: @source, amount: 100)

    Account::BalanceRefresh.call(@source)

    assert_equal 1000, @source.reload.balance
  end

  test "missing exchange rate defers refresh without publishing partial balances" do
    first, second = [ @source, @destination ].sort_by(&:id)
    create_transaction(account: first, amount: 100)
    create_transaction(account: second, amount: 100, currency: "EUR")
    ExchangeRate.stubs(:find_or_fetch_rate).returns(nil)
    first.expects(:broadcast_refresh).never
    second.expects(:broadcast_refresh).never

    assert_difference "DebugLogEntry.count", 1 do
      assert_equal false, Account::BalanceRefresh.call([ first, second ])
    end

    assert_equal 1000, first.reload.balance
    assert_equal 1000, second.reload.balance
    diagnostic = DebugLogEntry.order(:created_at).last
    assert_equal first.family, diagnostic.family
    assert_equal [ first.id, second.id ], diagnostic.metadata["account_ids"]
    assert_equal "EUR", diagnostic.metadata["from_currency"]
  end
end
