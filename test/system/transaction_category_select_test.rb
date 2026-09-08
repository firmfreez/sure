require "application_system_test_case"

class TransactionCategorySelectTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
  end

  test "mobile category list expands in the form with touch sized options" do
    page.current_window.resize_to(375, 812)
    visit new_transaction_url

    within "[data-controller='category-select']" do
      find("button", match: :first).click
      menu = find("[data-category-select-target='menu']")
      assert_equal "static", menu.evaluate_script("getComputedStyle(this).position")
      assert_no_selector "input[type='search']:focus"
      option = find("[role='option']", match: :first)
      assert_operator option.evaluate_script("this.getBoundingClientRect().height"), :>=, 48

      search = find("input[type='search']")
      search.set(categories(:food_and_drink).name)
      find("[role='option'][data-category-id='#{categories(:food_and_drink).id}']").click
      assert_selector "[data-category-select-target='hiddenInput'][value='#{categories(:food_and_drink).id}']", visible: :all
      assert_no_selector "[data-category-select-target='menu']"
      assert_selector "[data-category-select-target='button']:focus"

      find("[data-category-select-target='button']").click
      find("[data-category-select-target='button']").send_keys(:escape)
      assert_no_selector "[data-category-select-target='menu']"
    end
  end

  test "positioned lists remain usable when resized to mobile" do
    visit new_transaction_url
    find("summary", text: /details/i).click

    [ "select", "merchant-select", "tag-select" ].each do |controller|
      page.current_window.resize_to(1400, 1400)
      trigger = find("[data-#{controller}-target='button']", match: :first)
      trigger.click
      menu_selector = "[data-#{controller}-target='menu']"
      assert_selector "#{menu_selector}[style*='max-height']"

      page.current_window.resize_to(375, 812)
      assert_no_selector "#{menu_selector}[style*='max-height']"
      assert_equal "static", find(menu_selector).evaluate_script("getComputedStyle(this).position")
      trigger.click
      assert_no_selector menu_selector
      trigger.click

      within menu_selector do
        assert_no_selector "input[type='search']:focus"
        option = find("[role='option']", match: :first)
        assert_operator option.evaluate_script("this.getBoundingClientRect().height"), :>=, 48
        option.click
      end

      if controller == "tag-select"
        assert_selector "[data-tag-select-target='option'][aria-selected='true']"
        trigger.click
      else
        assert_no_selector menu_selector
      end
    end
  end

  test "can create a category from the transaction form" do
    visit new_transaction_url

    assert_difference "Category.count", +1 do
      find("[data-controller='category-select'] button").click

      within "[data-controller='category-select']" do
        fill_in "Search categories", with: "Inline Test Category"

        assert_text 'Create "Inline Test Category"'
        click_button 'Create "Inline Test Category"'

        assert_selector(
          "[data-category-select-target='option'][aria-selected='true']",
          text: "Inline Test Category",
          visible: :all
        )
      end
    end

    assert Category.exists?(name: "Inline Test Category")
  end

  test "can clear a category from an existing transaction" do
    transaction = transactions(:one)
    transaction.update!(category: categories(:food_and_drink))
    entry = transaction.entry

    visit transactions_url

    page.execute_script <<~JS
      const frame = document.querySelector("turbo-frame#drawer")
      frame.src = "#{transaction_url(entry)}"
    JS

    within "turbo-frame#drawer", visible: :all do
      assert_selector "[data-controller='category-select']"

      within "[data-controller='category-select']" do
        find("button", match: :first).click
        click_button "(uncategorized)"
      end
    end

    assert_selector(
      "##{ActionView::RecordIdentifier.dom_id(entry)}",
      text: "Uncategorized"
    )

    assert_nil transaction.reload.category_id
  end
end
