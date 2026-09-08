require "application_system_test_case"

class TransfersTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
    visit transactions_url
  end

  test "new transfer amount stays empty after selecting accounts and leaving the field" do
    click_on "New transaction"
    click_on "Transfer"

    assert_field "transfer[amount]", with: ""
    select_ds("From", accounts(:depository))
    select_ds("To", accounts(:credit_card))
    find_field("transfer[amount]").click
    find_field("transfer[amount]").send_keys(:tab)

    assert_field "transfer[amount]", with: ""
  end

  test "type tabs carry the amount and remember the name while in a transfer" do
    click_on "New transaction"
    fill_in "entry_name", with: "Rent & utilities"
    find("input[name='entry[amount]']").set("12,50+4,30")

    click_on "Income"
    assert_field "entry_name", with: "Rent & utilities"
    click_on "Transfer"
    assert_equal 16.8.to_d, find_field("transfer[amount]").value.to_d
    assert_selector "input[type=hidden][name=draft_name][value='Rent & utilities']", visible: :all

    fill_in "transfer[amount]", with: "87.65"
    click_on "Expense"
    assert_field "entry_name", with: "Rent & utilities"
    assert_equal 87.65.to_d, find_field("entry[amount]").value.to_d

    fill_in "entry_name", with: "Updated name"
    find_field("entry[amount]").set("")
    click_on "Transfer"
    assert_field "transfer[amount]", with: ""
    click_on "Income"
    assert_field "entry_name", with: "Updated name"
    assert_field "entry[amount]", with: ""

    visit transactions_url
    click_on "New transaction"
    assert_field "entry_name", with: ""
    assert_field "entry[amount]", with: ""
  end

  test "mobile name draft survives closing the picker and switching forms" do
    click_on "New transaction"
    page.current_window.resize_to(390, 844)
    find("#entry_name").click

    within "dialog.hw-combobox__dialog" do
      input = find("input[role='combobox']")
      input.set("Mobile draft")
      input.send_keys(:enter)
    end

    assert_field "entry_name", with: "Mobile draft"
    find_field("entry[amount]").set("12.34")
    click_on "Transfer"
    assert_equal 12.34.to_d, find_field("transfer[amount]").value.to_d
    click_on "Expense"
    assert_field "entry_name", with: "Mobile draft"
  end

  test "changing a preselected source fills an empty destination with its previous account" do
    from = accounts(:depository)
    to = accounts(:credit_card)
    open_transfer_from(from)

    assert_equal "", find("input[name='transfer[to_account_id]']", visible: :all).value
    select_ds("From", to)

    assert_transfer_accounts(from: to, to: from)
    assert_field "transfer[amount]", with: ""
  end

  test "choosing the destination as source swaps the accounts" do
    from = accounts(:depository)
    to = accounts(:credit_card)
    open_transfer_from(from)
    select_ds("To", to)
    fill_in "transfer[amount]", with: "123.45"

    select_ds("From", to)

    assert_transfer_accounts(from: to, to: from)
    assert_field "transfer[amount]", with: "123.45"
    assert_selector "#from_account_id_trigger:focus"
  end

  test "choosing another source preserves an already selected destination" do
    from = accounts(:depository)
    to = accounts(:credit_card)
    another = accounts(:connected)
    open_transfer_from(from)
    select_ds("To", to)

    select_ds("From", another)

    assert_transfer_accounts(from: another, to: to)
  end

  test "swapping accounts refreshes the exchange rate for the new direction" do
    usd = accounts(:depository)
    eur = @user.family.accounts.create!(name: "EUR source", currency: "EUR", balance: 1000, accountable: Depository.new)
    ExchangeRate.create!(from_currency: "USD", to_currency: "EUR", date: Date.current, rate: 0.92)
    ExchangeRate.create!(from_currency: "EUR", to_currency: "USD", date: Date.current, rate: 1.09)
    open_transfer_from(usd)
    select_ds("To", eur)
    assert_field "transfer[exchange_rate]", with: "0.92"

    select_ds("From", eur)

    assert_transfer_accounts(from: eur, to: usd)
    assert_field "transfer[exchange_rate]", with: "1.09"
    fill_in "transfer[amount]", with: "100"
    assert_selector "[data-transfer-form-target='convertDestinationDisplay']", text: "109.00 USD"
  end

  test "can create a transfer" do
    transfer_date = Date.current

    click_on "New transaction"
    click_on "Transfer"
    assert_text "New transfer"

    # Select accounts using DS::Select
    select_ds("From", accounts(:depository))
    select_ds("To", accounts(:credit_card))

    fill_in "transfer[amount]", with: 500
    fill_in "Date", with: transfer_date

    click_button "Create transfer"

    within "#entry-group-#{transfer_date}" do
      assert_text "Payment to"
    end
  end

  test "shows exchange rate field for different currencies" do
    # Create an account with a different currency
    eur_account = @user.family.accounts.create!(
      name: "EUR Savings",
      balance: 1000,
      currency: "EUR",
      accountable: Depository.new
    )

    # Set up exchange rate
    ExchangeRate.create!(
      from_currency: "USD",
      to_currency: "EUR",
      date: Date.current,
      rate: 0.92
    )

    transfer_date = Date.current

    click_on "New transaction"
    click_on "Transfer"
    assert_text "New transfer"

    # Initially, exchange rate field should be hidden
    assert_selector "[data-transfer-form-target='exchangeRateContainer'].hidden", visible: :all

    # Select accounts with different currencies
    select_ds("From", accounts(:depository))
    select_ds("To", eur_account)

    # Exchange rate container should become visible
    assert_selector "[data-transfer-form-target='exchangeRateContainer']", visible: true

    # Exchange rate field should be populated with fetched rate
    exchange_rate_field = find("[data-transfer-form-target='exchangeRateField']")
    assert_not_empty exchange_rate_field.value
    assert_equal "0.92", exchange_rate_field.value

    # Fill in amount
    fill_in "transfer[amount]", with: 100
    fill_in "Date", with: transfer_date

    # Submit form
    click_button "Create transfer"

    # Should redirect and show transfer created
    assert_current_path transactions_url
    within "#entry-group-#{transfer_date}" do
      assert_text "Transfer to"
    end
  end

  private

    def open_transfer_from(account)
      visit account_url(account, tab: "activity")
      within "[data-testid='activity-menu']" do
        click_button "New"
        click_link "New transfer"
      end
    end

    def assert_transfer_accounts(from:, to:)
      assert_selector "input[name='transfer[from_account_id]'][value='#{from.id}']", visible: :all
      assert_selector "input[name='transfer[to_account_id]'][value='#{to.id}']", visible: :all
      assert_selector "#from_account_id_trigger", text: from.name
      assert_selector "#to_account_id_trigger", text: to.name
    end

    def select_ds(label_text, record)
      field_label = find("label", exact_text: label_text)
      container = field_label.ancestor("div.relative")

      # Click the button to open the dropdown
      container.find("button").click

      # If searchable, type in the search input
      if container.has_selector?("input[type='search']", visible: true)
        container.find("input[type='search']", visible: true).set(record.name)
      end

      # Wait for the listbox to appear inside the relative container
      listbox = container.find("[role='listbox']", visible: true)

      # Click the option inside the listbox
      listbox.find("[role='option'][data-value='#{record.id}']", visible: true).click
    end
end
