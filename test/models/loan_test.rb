require "test_helper"

class LoanTest < ActiveSupport::TestCase
  test "calculates correct monthly payment for fixed rate loan" do
    loan_account = Account.create! \
      family: families(:dylan_family),
      name: "Mortgage Loan",
      balance: 500000,
      currency: "USD",
      accountable: Loan.create!(
        interest_rate: 3.5,
        term_months: 360,
        rate_type: "fixed"
      )

    assert_equal 2245, loan_account.loan.monthly_payment.amount
  end

  test "uses remaining term and current balance for monthly payment" do
    loan_account = Account.create! \
      family: families(:dylan_family),
      name: "Mortgage Loan",
      balance: 90000,
      currency: "USD",
      accountable: Loan.create!(
        interest_rate: 6.0,
        term_months: 120,
        rate_type: "fixed"
      )

    loan_account.set_opening_anchor_balance(balance: 100000, date: Time.zone.today - 6.months)

    assert_equal 1038, loan_account.loan.monthly_payment.amount
    assert_equal 114, loan_account.loan.remaining_term_months
  end
end
