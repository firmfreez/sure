require "test_helper"

class UI::Account::ActivityDateTest < ViewComponent::TestCase
  setup do
    Current.session = sessions(:one)
    @date = 3.days.ago.to_date
    @data = Account::ActivityFeedData::ActivityDateData.new(
      date: @date, entries: [], balance: nil, transfers: [], split_parents: {}
    )
  end

  teardown do
    Current.reset
  end

  test "day shortcut opens a transaction for that account and date" do
    account = accounts(:depository)
    render_inline(UI::Account::ActivityDate.new(account: account, data: @data))

    assert_selector "summary a[data-turbo-frame='modal'][aria-label]" do |link|
      uri = URI.parse(link[:href])
      params = Rack::Utils.parse_query(uri.query)
      assert_equal "/transactions/new", uri.path
      assert_equal account.id, params["account_id"]
      assert_equal @date.iso8601, params["date"]
      assert_equal "/accounts/#{account.id}?tab=activity", params["return_to"]
    end
  end

  test "investment day shortcut opens trade creation with the date" do
    account = accounts(:investment)
    render_inline(UI::Account::ActivityDate.new(account: account, data: @data))

    assert_selector "summary a[data-turbo-frame='modal']" do |link|
      uri = URI.parse(link[:href])
      assert_equal "/trades/new", uri.path
      assert_equal({ "account_id" => account.id, "date" => @date.iso8601 }, Rack::Utils.parse_query(uri.query))
    end
  end

  test "crypto day shortcut opens a transfer with the date" do
    account = accounts(:crypto)
    render_inline(UI::Account::ActivityDate.new(account: account, data: @data))

    assert_selector "summary a[data-turbo-frame='modal']" do |link|
      uri = URI.parse(link[:href])
      params = Rack::Utils.parse_query(uri.query)
      assert_equal "/transfers/new", uri.path
      assert_equal account.id, params["from_account_id"]
      assert_equal @date.iso8601, params["date"]
    end
  end

  test "day shortcut is hidden without permission to create entries" do
    account = accounts(:credit_card)
    Current.session = Session.new(user: users(:family_member))

    render_inline(UI::Account::ActivityDate.new(account: account, data: @data))

    assert_no_selector "summary a[data-turbo-frame='modal']"
  end
end
