require "test_helper"

class BudgetTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
  end

  test "budget_date_valid? allows going back 2 years even without entries" do
    two_years_ago = 2.years.ago.beginning_of_month
    assert Budget.budget_date_valid?(two_years_ago, family: @family)
  end

  test "budget_date_valid? allows going back to earliest entry date if more than 2 years ago" do
    # Create an entry 3 years ago
    old_account = Account.create!(
      family: @family,
      accountable: Depository.new,
      name: "Old Account",
      status: "active",
      currency: "USD",
      balance: 1000
    )

    old_entry = Entry.create!(
      account: old_account,
      entryable: Transaction.new(category: categories(:income)),
      date: 3.years.ago,
      name: "Old Transaction",
      amount: 100,
      currency: "USD"
    )

    # Should allow going back to the old entry date
    assert Budget.budget_date_valid?(3.years.ago.beginning_of_month, family: @family)
  end

  test "budget_date_valid? does not allow dates before earliest entry or 2 years ago" do
    # Create an entry 1 year ago
    account = Account.create!(
      family: @family,
      accountable: Depository.new,
      name: "Test Account",
      status: "active",
      currency: "USD",
      balance: 500
    )

    Entry.create!(
      account: account,
      entryable: Transaction.new(category: categories(:income)),
      date: 1.year.ago,
      name: "Recent Transaction",
      amount: 100,
      currency: "USD"
    )

    # Should not allow going back more than 2 years
    refute Budget.budget_date_valid?(3.years.ago.beginning_of_month, family: @family)
  end

  test "budget_date_valid? does not allow future dates beyond current month" do
    refute Budget.budget_date_valid?(2.months.from_now, family: @family)
  end

  test "previous_budget_param returns nil when date is too old" do
    # Create a budget at the oldest allowed date
    two_years_ago = 2.years.ago.beginning_of_month
    budget = Budget.create!(
      family: @family,
      start_date: two_years_ago,
      end_date: two_years_ago.end_of_month,
      currency: "USD"
    )

    assert_nil budget.previous_budget_param
  end

  test "actual_spending nets refunds against expenses in same category" do
    family = families(:dylan_family)
    budget = Budget.find_or_bootstrap(family, start_date: Date.current.beginning_of_month)

    healthcare = Category.create!(
      name: "Healthcare #{Time.now.to_f}",
      family: family,
      color: "#e74c3c",
      classification: "expense"
    )

    budget.sync_budget_categories
    budget_category = budget.budget_categories.find_by(category: healthcare)
    budget_category.update!(budgeted_spending: 200)

    account = accounts(:depository)

    # Create a $500 expense
    Entry.create!(
      account: account,
      entryable: Transaction.create!(category: healthcare),
      date: Date.current,
      name: "Doctor visit",
      amount: 500,
      currency: "USD"
    )

    # Create a $200 refund (negative amount = income classification in the SQL)
    Entry.create!(
      account: account,
      entryable: Transaction.create!(category: healthcare),
      date: Date.current,
      name: "Insurance reimbursement",
      amount: -200,
      currency: "USD"
    )

    # Clear memoized values
    budget = Budget.find(budget.id)
    budget.sync_budget_categories

    # Budget category should show net spending: $500 - $200 = $300
    assert_equal 300, budget.budget_category_actual_spending(
      budget.budget_categories.find_by(category: healthcare)
    )
  end

  test "budget_category_actual_spending does not go below zero" do
    family = families(:dylan_family)
    budget = Budget.find_or_bootstrap(family, start_date: Date.current.beginning_of_month)

    category = Category.create!(
      name: "Returns Only #{Time.now.to_f}",
      family: family,
      color: "#3498db",
      classification: "expense"
    )

    budget.sync_budget_categories
    budget_category = budget.budget_categories.find_by(category: category)
    budget_category.update!(budgeted_spending: 100)

    account = accounts(:depository)

    # Only a refund, no expense
    Entry.create!(
      account: account,
      entryable: Transaction.create!(category: category),
      date: Date.current,
      name: "Full refund",
      amount: -50,
      currency: "USD"
    )

    budget = Budget.find(budget.id)
    budget.sync_budget_categories

    assert_equal 0, budget.budget_category_actual_spending(
      budget.budget_categories.find_by(category: category)
    )
  end

  test "actual_spending does not subtract uncategorized income" do
    family = families(:dylan_family)
    budget = Budget.find_or_bootstrap(family, start_date: Date.current.beginning_of_month)
    account = accounts(:depository)

    # Create an uncategorized expense
    Entry.create!(
      account: account,
      entryable: Transaction.create!(category: nil),
      date: Date.current,
      name: "Uncategorized purchase",
      amount: 400,
      currency: "USD"
    )

    # Create an uncategorized refund
    Entry.create!(
      account: account,
      entryable: Transaction.create!(category: nil),
      date: Date.current,
      name: "Uncategorized income",
      amount: -150,
      currency: "USD"
    )

    budget = Budget.find(budget.id)
    budget.sync_budget_categories

    spending_with_income = budget.actual_spending

    Entry.find_by(name: "Uncategorized income").destroy!
    budget = Budget.find(budget.id)
    spending_without_income = budget.actual_spending

    assert_equal spending_without_income, spending_with_income
  end

  test "budget_category_actual_spending ignores uncategorized income" do
    family = families(:dylan_family)
    budget = Budget.find_or_bootstrap(family, start_date: Date.current.beginning_of_month)
    account = accounts(:depository)

    uncategorized_bc = budget.uncategorized_budget_category
    baseline = budget.budget_category_actual_spending(uncategorized_bc)

    Entry.create!(
      account: account,
      entryable: Transaction.create!(category: nil),
      date: Date.current,
      name: "Uncategorized test expense",
      amount: 400,
      currency: "USD"
    )

    Entry.create!(
      account: account,
      entryable: Transaction.create!(category: nil),
      date: Date.current,
      name: "Uncategorized test income",
      amount: -100,
      currency: "USD"
    )

    budget = Budget.find(budget.id)
    budget.sync_budget_categories
    uncategorized_bc = budget.uncategorized_budget_category

    assert_equal baseline + 400, budget.budget_category_actual_spending(uncategorized_bc)
  end

  test "to_donut_segments_json includes uncategorized spending" do
    family = families(:dylan_family)
    budget = Budget.find_or_bootstrap(family, start_date: Date.current.beginning_of_month)
    account = family.accounts.create!(
      accountable: Depository.new,
      name: "Budget test account #{SecureRandom.hex(4)}",
      status: "active",
      currency: family.currency,
      balance: 0
    )

    # Make allocations deterministic for this test so donut segments are rendered
    # from real category data rather than the fallback "unused" segment.
    budget.budget_categories.update_all(budgeted_spending: 0)
    budget.budget_categories
      .joins(:category)
      .where(categories: { parent_id: nil })
      .first
      .update!(budgeted_spending: 500)
    budget.update!(budgeted_spending: 1000)

    Entry.create!(
      account: account,
      entryable: Transaction.create!(category: nil),
      date: Date.current,
      name: "Uncategorized donut expense",
      amount: 200,
      currency: family.currency
    )

    budget = Budget.find(budget.id)
    budget.sync_budget_categories

    uncategorized_bc = budget.uncategorized_budget_category
    expected_uncategorized_spending = budget.budget_category_actual_spending(uncategorized_bc)
    segments = budget.to_donut_segments_json

    assert expected_uncategorized_spending.positive?
    uncategorized_segment = segments.find { |segment| segment[:id].to_s == uncategorized_bc.id.to_s }
    assert uncategorized_segment.present?, "Expected uncategorized segment id=#{uncategorized_bc.id.inspect}, got: #{segments.inspect}"
    assert_equal expected_uncategorized_spending, uncategorized_segment[:amount]
  end

  test "category_avg_monthly_expense includes subcategory averages for parent categories" do
    family = families(:dylan_family)
    budget = Budget.find_or_bootstrap(family, start_date: Date.current.beginning_of_month)

    parent = Category.create!(
      name: "Transport Avg #{Time.now.to_f}",
      family: family,
      color: "#6471eb",
      classification: "expense"
    )

    fuel = Category.create!(
      name: "Fuel Avg #{Time.now.to_f}",
      family: family,
      parent: parent,
      classification: "expense"
    )

    parking = Category.create!(
      name: "Parking Avg #{Time.now.to_f}",
      family: family,
      parent: parent,
      classification: "expense"
    )

    income_statement = mock
    budget.stubs(:income_statement).returns(income_statement)

    income_statement.stubs(:avg_expense).with(category: parent).returns(577)
    income_statement.stubs(:avg_expense).with(category: fuel).returns(4549)
    income_statement.stubs(:avg_expense).with(category: parking).returns(4000)

    assert_equal 9126, budget.category_avg_monthly_expense(parent)
    assert_equal 4549, budget.category_avg_monthly_expense(fuel)
    assert_equal 4000, budget.category_avg_monthly_expense(parking)
  end

  test "previous_budget_param returns param when date is valid" do
    budget = Budget.create!(
      family: @family,
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      currency: "USD"
    )

    assert_not_nil budget.previous_budget_param
  end
end
