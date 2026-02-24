class Loan < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "mortgage" => { short: "Mortgage", long: "Mortgage" },
    "student" => { short: "Student", long: "Student Loan" },
    "auto" => { short: "Auto", long: "Auto Loan" },
    "other" => { short: "Other", long: "Other Loan" }
  }.freeze

  def monthly_payment
    return nil if interest_rate.nil? || rate_type != "fixed"

    remaining_months = remaining_term_months
    return nil if remaining_months.nil?

    current_principal = account.balance_money
    return Money.new(0, account.currency) if current_principal.amount.zero? || remaining_months.zero?

    annual_rate = interest_rate / 100.0
    monthly_rate = annual_rate / 12.0
    principal = current_principal.amount

    if monthly_rate.zero?
      payment = principal / remaining_months
    else
      payment = (principal * monthly_rate * (1 + monthly_rate)**remaining_months) / ((1 + monthly_rate)**remaining_months - 1)
    end

    Money.new(payment.round, account.currency)
  end

  def remaining_term_months
    return nil if term_months.nil?

    start_date = account.opening_anchor_date
    return term_months if start_date.nil?

    months_elapsed = months_between(start_date, Time.zone.today)
    remaining = term_months - months_elapsed
    remaining.positive? ? remaining : 0
  end

  def original_balance
    Money.new(account.first_valuation_amount, account.currency)
  end

  class << self
    def color
      "#D444F1"
    end

    def icon
      "hand-coins"
    end

    def classification
      "liability"
    end
  end

  private
    def months_between(start_date, end_date)
      return 0 if end_date < start_date

      months = (end_date.year * 12 + end_date.month) - (start_date.year * 12 + start_date.month)
      months -= 1 if end_date.day < start_date.day
      [ months, 0 ].max
    end
end
