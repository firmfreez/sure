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

  [ [ "mobile", 375, 812, 8 ], [ "desktop", 1400, 1000, 10 ] ].each do |layout, width, height, minimum_visible|
    test "a long #{layout} category list has room to browse and select its final options" do
      last_category = 30.times.map do |index|
        @user.family.categories.create!(name: "Scrollable #{index.to_s.rjust(2, '0')}", color: categories(:food_and_drink).color)
      end.last
      page.current_window.resize_to(width, height)
      visit new_transaction_url
      find("[data-controller='category-select'] button").click

      list = find("[data-category-select-target='list']")
      page.document.synchronize do
        visible_count = list.evaluate_script(<<~JS)
          (() => {
            const bounds = this.getBoundingClientRect();
            const top = Math.max(bounds.top, 0);
            const bottom = Math.min(bounds.bottom, window.innerHeight);
            return Array.from(this.querySelectorAll("[role='option']")).filter((option) => {
              const row = option.getBoundingClientRect();
              return row.height > 0 && row.top >= top && row.bottom <= bottom;
            }).length;
          })()
        JS
        raise Capybara::ExpectationNotMet, "Only #{visible_count} category options fit in view" if visible_count < minimum_visible
      end

      assert_operator list.evaluate_script("this.clientHeight"), :<, page.evaluate_script("window.innerHeight")
      assert_operator list.evaluate_script("this.scrollHeight"), :>, list.evaluate_script("this.clientHeight")
      list.execute_script("this.scrollTop = this.scrollHeight")
      find("[role='option'][data-category-id='#{last_category.id}']").click

      assert_selector "[data-category-select-target='hiddenInput'][value='#{last_category.id}']", visible: :all
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
        find("button[data-category-id='']").click
      end
    end

    assert_selector(
      "##{ActionView::RecordIdentifier.dom_id(entry)}",
      text: "Uncategorized"
    )

    assert_nil transaction.reload.category_id
  end

  test "can create a subcategory from the transaction form" do
    parent = categories(:food_and_drink)
    visit new_transaction_url

    assert_difference "Category.count", +1 do
      find("[data-controller='category-select'] button").click

      within "[data-controller='category-select']" do
        fill_in "Search categories", with: "Inline Subcategory"
        click_button "Add as a subcategory…"

        assert_text 'Create "Inline Subcategory" under:'
        find("button[data-parent-id='#{parent.id}']").click

        assert_selector "[data-category-select-target='selectionContainer']", text: "Inline Subcategory"
      end
    end

    assert_equal parent, Category.find_by!(name: "Inline Subcategory").parent
  end

  test "can create a subcategory from the transaction details panel" do
    parent = categories(:food_and_drink)
    transaction = transactions(:one)
    entry = transaction.entry

    visit transactions_url

    page.execute_script <<~JS
      const frame = document.querySelector("turbo-frame#drawer")
      frame.src = "#{transaction_url(entry)}"
    JS

    within "turbo-frame#drawer", visible: :all do
      within "[data-controller='category-select']" do
        find("button", match: :first).click
        fill_in "Search categories", with: "Drawer Subcategory"
        click_button "Add as a subcategory…"
        find("button[data-parent-id='#{parent.id}']").click
      end
    end

    assert_selector "##{ActionView::RecordIdentifier.dom_id(entry)}", text: "Drawer Subcategory"

    category = Category.find_by!(name: "Drawer Subcategory")
    assert_equal parent, category.parent
    assert_equal category.id, transaction.reload.category_id
  end

  test "back from the parent picker returns to the category list" do
    visit new_transaction_url
    find("[data-controller='category-select'] button").click

    within "[data-controller='category-select']" do
      fill_in "Search categories", with: "Changed My Mind"
      click_button "Add as a subcategory…"
      assert_selector "[data-category-select-target='parentPicker']", visible: true

      click_button "Back"
      assert_no_selector "[data-category-select-target='parentPicker']", visible: true
      assert_button 'Create "Changed My Mind"'
    end
  end

  test "the parent picker keeps keyboard focus, and Escape steps back out" do
    visit new_transaction_url
    find("[data-controller='category-select'] button").click

    within "[data-controller='category-select']" do
      fill_in "Search categories", with: "Keyboard Category"
      click_button "Add as a subcategory…"
    end

    assert_equal "parentOption", active_element_attribute("data-category-select-target")

    send_escape
    assert_no_selector "[data-category-select-target='parentPicker']", visible: true
    assert_equal "search", active_element_attribute("data-category-select-target")

    send_escape
    assert_no_selector "[data-category-select-target='menu']", visible: true
    assert_equal "button", active_element_attribute("data-category-select-target")
  end

  test "Enter in the search while the parent picker is open doesn't create a top-level category" do
    visit new_transaction_url
    find("[data-controller='category-select'] button").click

    within "[data-controller='category-select']" do
      fill_in "Search categories", with: "Not Top Level"
      click_button "Add as a subcategory…"
    end

    assert_no_difference "Category.count" do
      page.execute_script("document.querySelector(\"[data-category-select-target='search']\").focus()")
      find("[data-category-select-target='search']").send_keys(:enter)
      assert_selector "[data-category-select-target='parentPicker']", visible: true
      assert_equal "parentOption", active_element_attribute("data-category-select-target")
    end
  end

  test "Enter in the category search picks the match while categories are locked" do
    @user.family.update!(categories_locked: true)
    visit new_transaction_url(account_id: accounts(:depository).id)
    fill_in "entry_name", with: "Locked picker"
    find("input[name='entry[amount]']").set("12.34")

    assert_no_difference "Entry.count" do
      find("[data-controller='category-select'] button").click

      within "[data-controller='category-select']" do
        fill_in "Search categories", with: "Food"
        find_field("Search categories").send_keys(:enter)

        assert_selector "[data-category-select-target='selectionContainer']", text: "Food & Drink"
      end
    end
  end

  test "Enter selects an existing category from a partial search instead of creating one" do
    visit new_transaction_url(account_id: accounts(:depository).id)
    fill_in "entry_name", with: "Keyboard category selection"
    find("input[name='entry[amount]']").set("12.34")

    assert_no_difference [ "Category.count", "Entry.count" ] do
      find("[data-controller='category-select'] button").click

      within "[data-controller='category-select']" do
        fill_in "Search categories", with: "Food"
        assert_button 'Create "Food"'
        find_field("Search categories").send_keys(:enter)

        assert_selector "[data-category-select-target='hiddenInput'][value='#{categories(:food_and_drink).id}']", visible: :all
        assert_no_selector "[data-category-select-target='menu']"
        assert_selector "[data-category-select-target='button']:focus"
      end
    end
  end

  test "Enter with no matching category keeps the form open without creating a category" do
    visit new_transaction_url(account_id: accounts(:depository).id)
    fill_in "entry_name", with: "Unmatched category search"
    find("input[name='entry[amount]']").set("12.34")

    assert_no_difference [ "Category.count", "Entry.count" ] do
      find("[data-controller='category-select'] button").click

      within "[data-controller='category-select']" do
        fill_in "Search categories", with: "No matching category"
        find_field("Search categories").send_keys(:enter)

        assert_button 'Create "No matching category"', disabled: false
        assert_selector "[data-category-select-target='menu']"
        assert_field "Search categories", with: "No matching category"
        assert_selector "[data-category-select-target='hiddenInput'][value='']", visible: :all
      end
    end
  end

  test "search keeps the parent visible for a matching subcategory and Enter selects the match" do
    parent = categories(:food_and_drink)
    child = categories(:subcategory)
    visit new_transaction_url
    find("[data-controller='category-select'] button").click

    within "[data-controller='category-select']" do
      fill_in "Search categories", with: "Rest"

      assert_selector "[role='option'][data-category-id='#{parent.id}']"
      assert_selector "[role='option'][data-category-id='#{child.id}']"
      assert_no_selector "[role='option'][data-category-id='#{categories(:income).id}']"

      find_field("Search categories").send_keys(:enter)

      assert_selector "[data-category-select-target='hiddenInput'][value='#{child.id}']", visible: :all
      assert_no_selector "[data-category-select-target='menu']"
    end
  end

  test "search distinguishes a root category from a same-name child by keeping its parent" do
    parent = categories(:food_and_drink)
    parent.update!(name: "Жильё")
    root = @user.family.categories.create!(name: "Квартира", color: parent.color)
    child = @user.family.categories.create!(name: "Квартира", parent: parent, color: parent.color)
    visit new_transaction_url
    find("[data-controller='category-select'] button").click

    within "[data-controller='category-select']" do
      fill_in "Search categories", with: "Квартира"

      assert_selector "[role='option'][data-category-id='#{parent.id}']", text: "Жильё"
      assert_selector "[role='option'][data-category-id='#{root.id}']", text: "Квартира"
      assert_selector "[role='option'][data-category-id='#{child.id}'][data-category-parent-id='#{parent.id}']", text: "Квартира"
      assert_no_selector "[role='option'][data-category-id='#{categories(:income).id}']"

      fill_in "Search categories", with: ""
      assert_selector "[role='option'][data-category-id='#{categories(:income).id}']"
    end
  end

  test "a new subcategory is listed under its parent straight away" do
    parent = categories(:food_and_drink)
    visit new_transaction_url
    find("[data-controller='category-select'] button").click

    within "[data-controller='category-select']" do
      fill_in "Search categories", with: "Grouped Subcategory"
      click_button "Add as a subcategory…"
      find("button[data-parent-id='#{parent.id}']").click
      # The rows stay disabled until the POST returns; give a slow request time.
      assert_selector "[data-category-select-target='selectionContainer']", text: "Grouped Subcategory", wait: 10
    end

    created = Category.find_by!(name: "Grouped Subcategory")
    group_ids = [ parent.id, *parent.subcategories.where.not(id: created.id).pluck(:id) ].map(&:to_s)
    previous_id = page.evaluate_script(<<~JS)
      document.querySelector("[data-category-select-target='option'][data-category-id='#{created.id}']")
        .previousElementSibling.dataset.categoryId
    JS
    assert_includes group_ids, previous_id
  end

  test "a failed create from the parent picker returns to the list with the error" do
    parent = categories(:food_and_drink)
    visit new_transaction_url
    find("[data-controller='category-select'] button").click

    within "[data-controller='category-select']" do
      fill_in "Search categories", with: "Late Duplicate"
      click_button "Add as a subcategory…"
    end

    # Someone else takes the name under this parent after the page loaded.
    Category.create!(family: parent.family, parent: parent, name: "Late Duplicate", color: "#e99537")

    within "[data-controller='category-select']" do
      find("button[data-parent-id='#{parent.id}']").click

      assert_selector "[role='alert']", text: "taken", wait: 10
      assert_no_selector "[data-category-select-target='parentPicker']", visible: true
    end
    assert_keyboard_back_in_search
  end

  test "a failed top-level create keeps focus in the menu" do
    visit new_transaction_url
    find("[data-controller='category-select'] button").click

    within "[data-controller='category-select']" do
      fill_in "Search categories", with: "Late Top Level"
    end
    Category.create!(family: users(:family_admin).family, name: "Late Top Level", color: "#e99537")

    within "[data-controller='category-select']" do
      find("[data-category-select-target='createForm']").click
      assert_selector "[role='alert']", text: "taken", wait: 10
    end
    assert_keyboard_back_in_search
  end

  test "a top-level category created inline is offered as a parent without reloading" do
    visit new_transaction_url
    find("[data-controller='category-select'] button").click

    within "[data-controller='category-select']" do
      fill_in "Search categories", with: "Fresh Parent"
      click_button 'Create "Fresh Parent"'
      assert_selector "[data-category-select-target='selectionContainer']", text: "Fresh Parent"
    end

    fresh_parent = Category.find_by!(name: "Fresh Parent")
    find("[data-controller='category-select'] button").click

    within "[data-controller='category-select']" do
      fill_in "Search categories", with: "Fresh Child"
      click_button "Add as a subcategory…"
      find("button[data-parent-id='#{fresh_parent.id}']").click
      assert_selector "[data-category-select-target='selectionContainer']", text: "Fresh Child"
    end

    assert_equal fresh_parent, Category.find_by!(name: "Fresh Child").parent
  end

  private
    def active_element_attribute(name)
      page.evaluate_script("document.activeElement.getAttribute('#{name}')")
    end

    def send_escape
      page.driver.browser.action.send_keys(:escape).perform
    end

    # Focus is back in the search, so Escape closes the menu, not the
    # New transaction dialog around it.
    def assert_keyboard_back_in_search
      assert_equal "search", active_element_attribute("data-category-select-target")
      send_escape
      assert_no_selector "[data-category-select-target='menu']", visible: true
      assert_selector "dialog[open]"
    end
end
