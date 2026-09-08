require "application_system_test_case"

class AccountActivityTest < ApplicationSystemTestCase
  DEFAULT_VIEWPORT_WIDTH = 1400
  DEFAULT_VIEWPORT_HEIGHT = 1400

  setup do
    ensure_tailwind_build
    sign_in users(:family_admin)
    reset_viewport

    @account = accounts(:depository)
    @transaction_entry = @account.entries.create!(
      name: "Duplicate source",
      date: Date.current,
      amount: 42.50,
      currency: "USD",
      entryable: Transaction.new(category: categories(:food_and_drink))
    )
    @valuation_entry = @account.entries.create!(
      name: "Current balance",
      date: 1.day.ago.to_date,
      amount: 1000,
      currency: "USD",
      entryable: Valuation.new
    )
  end

  test "day shortcut prefills the date through expense income and transfer tabs" do
    date = @valuation_entry.date
    visit account_url(@account, tab: "activity")

    within "##{dom_id(@account, "entries_#{date}")}" do
      find("summary a[data-turbo-frame='modal']").click
    end

    within "turbo-frame#modal" do
      assert_selector "input[name='entry[date]'][value='#{date.iso8601}']"
      click_link "Income"
      assert_selector "input[name='entry[nature]'][value='inflow']", visible: :all
      assert_selector "input[name='entry[date]'][value='#{date.iso8601}']"
      click_link "Transfer"
      assert_selector "input[name='transfer[date]'][value='#{date.iso8601}']"
      click_link "Expense"
      assert_selector "input[name='entry[date]'][value='#{date.iso8601}']"
    end
  end

  test "remembers the entered date and Today resets it across new forms" do
    date = 5.days.ago.to_date
    open_new_activity_transaction
    find("input[name='entry[date]']").set(date)
    wait_for_remembered_date(date)

    open_new_activity_transaction
    assert_equal date.iso8601, find("input[name='entry[date]']").value

    click_link "Transfer"
    assert_equal date.iso8601, find("input[name='transfer[date]']").value
    click_button "Today"
    assert_equal Date.current.iso8601, find("input[name='transfer[date]']").value
    wait_for_remembered_date(Date.current)

    click_link "Expense"
    assert_equal Date.current.iso8601, find("input[name='entry[date]']").value

    visit new_trade_url(account_id: accounts(:investment).id)
    assert_equal Date.current.iso8601, find("input[name='model[date]']").value
  end

  test "account activity shows duplicate action for a selected transaction" do
    visit account_url(@account, tab: "activity")

    find("#" + dom_id(@transaction_entry, "selection")).check

    within "#entry-selection-bar" do
      assert_selector "a[title='Duplicate']:not(.hidden)"
    end
  end

  test "account activity hides duplicate action for a selected valuation" do
    visit account_url(@account, tab: "activity")

    find("#" + dom_id(@valuation_entry, "selection")).check

    within "#entry-selection-bar" do
      assert_selector "a[title='Duplicate'].hidden", visible: false
    end
  end

  test "account activity keeps long category names from overflowing the amount on mobile" do
    category = categories(:food_and_drink)
    category.update!(name: "Super Long Category Name That Should Stop Before The Amount On Mobile")

    page.current_window.resize_to(315, 643)

    visit account_url(@account, tab: "activity")

    row = find("##{dom_id(@transaction_entry)}")
    amount = row.find("p.privacy-sensitive", visible: true)
    category_name = row.find("#category_name_mobile_#{@transaction_entry.entryable.id}", visible: true)

    assert amount.visible?
    assert category_name.visible?

    row_rect = row.native.rect
    amount_rect = amount.native.rect
    viewport_width = page.evaluate_script("window.innerWidth")
    page_scroll_width = page.evaluate_script("document.documentElement.scrollWidth")

    assert_operator amount_rect.x + amount_rect.width, :<=, row_rect.x + row_rect.width
    assert_operator page_scroll_width, :<=, viewport_width
  end

  test "account activity filter menu has no account tab and can filter by category" do
    visit account_url(@account, tab: "activity")

    find("#activity-filters-button").click

    within "#transaction-filters-menu" do
      assert_no_selector "button[data-id='account_filter']"
      assert_selector "button[data-id='category_filter']"

      find("button[data-id='category_filter']").click
      check categories(:food_and_drink).name, allow_label_click: true
      click_button "Apply"
    end

    assert_selector "#account-activity-filters li", text: categories(:food_and_drink).name
    assert_selector "##{dom_id(@transaction_entry)}"
    assert_no_selector "##{dom_id(@valuation_entry)}"
  end

  test "clearing a filter badge on account activity removes just that filter" do
    visit account_url(@account, tab: "activity", q: { categories: [ categories(:food_and_drink).filter_value ] })

    assert_selector "#account-activity-filters li", text: categories(:food_and_drink).name

    within "#account-activity-filters li", text: categories(:food_and_drink).name do
      click_button
    end

    assert_no_selector "#account-activity-filters li"
    assert_selector "##{dom_id(@valuation_entry)}"
  end

  test "account activity keeps long category names from overlapping the amount on wide screens" do
    category = categories(:food_and_drink)
    category.update!(name: "Super Long Category Name That Should Stop Before The Amount On Wide Screens Too")

    page.current_window.resize_to(1280, 900)

    visit account_url(@account, tab: "activity")

    metrics = page.evaluate_script(<<~JS)
      (() => {
        const row = document.getElementById("#{dom_id(@transaction_entry)}");
        const categoryButton = row.querySelector("##{dom_id(@transaction_entry.entryable, "category_menu_desktop")} button");
        const categoryName = categoryButton.querySelector("[data-testid='category-name']");
        const amount = row.querySelector(".privacy-sensitive");
        const categoryRect = categoryButton.getBoundingClientRect();
        const amountRect = amount.getBoundingClientRect();

        return {
          categoryRight: categoryRect.right,
          amountLeft: amountRect.left,
          categoryOverflow: categoryName.scrollWidth > categoryName.clientWidth
        };
      })()
    JS

    assert_operator metrics["categoryRight"], :<=, metrics["amountLeft"]
    assert metrics["categoryOverflow"]
  end

  private
    def open_new_activity_transaction
      visit account_url(@account, tab: "activity")
      within "[data-testid='activity-menu']" do
        click_button "New"
        click_link "New transaction"
      end
    end

    def wait_for_remembered_date(date)
      page.document.synchronize do
        unless users(:family_admin).reload.last_entry_date == date
          raise Capybara::ExpectationNotMet, "Entry date preference has not been saved"
        end
      end
    end

    def ensure_tailwind_build
      return if self.class.instance_variable_defined?(:@tailwind_css_built)

      system({ "RAILS_ENV" => "test" }, "bin/rails", "tailwindcss:build", exception: true)
      self.class.instance_variable_set(:@tailwind_css_built, true)
    end

    def teardown
      reset_viewport
      super
    end

    def reset_viewport
      page.current_window.resize_to(DEFAULT_VIEWPORT_WIDTH, DEFAULT_VIEWPORT_HEIGHT) if page&.current_window
    end
end
