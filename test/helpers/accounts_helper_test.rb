require "test_helper"

class AccountsHelperTest < ActionView::TestCase
  setup do
    @user = users(:family_admin)
    Current.session = @user.sessions.create!
  end

  teardown { Current.session = nil }

  test "sidebar cache key changes with the account order" do
    @user.update!(default_account_order: "name_asc")
    name_key = sidebar_key

    @user.update!(default_account_order: "balance_desc")

    assert_not_equal name_key, sidebar_key
  end

  test "sidebar cache key changes when the manual order changes" do
    @user.update!(default_account_order: "manual")
    before = sidebar_key

    @user.update_manual_account_order("depository", [ accounts(:connected).id, accounts(:depository).id ])

    assert_not_equal before, sidebar_key
  end

  test "active account is recognized with and without an ingress mount" do
    account = accounts(:depository)
    request.path_info = "/accounts/#{account.id}"

    [ "", "/api/hassio_ingress/test" ].each do |mount|
      request.script_name = mount
      assert_equal account.id, sidebar_active_account_id
    end

    request.path_info = "/accounts/#{account.id}/holdings"
    assert_equal account.id, sidebar_active_account_id

    request.path_info = "/transactions"
    assert_nil sidebar_active_account_id
  end

  test "cached sidebar state is isolated between accounts behind ingress" do
    request.script_name = "/api/hassio_ingress/test"
    store = ActiveSupport::Cache::MemoryStore.new
    first, second = accounts(:depository), accounts(:credit_card)

    request.path_info = "/"
    store.write(sidebar_key, "closed groups")

    request.path_info = "/accounts/#{first.id}"
    assert_nil store.read(sidebar_key)
    store.write(sidebar_key, first.id)

    request.path_info = "/accounts/#{second.id}"
    assert_nil store.read(sidebar_key)
    store.write(sidebar_key, second.id)

    request.path_info = "/accounts/#{first.id}"
    assert_equal first.id, store.read(sidebar_key)
  end

  test "sidebar cache cannot reuse links from a different ingress mount" do
    request.path_info = "/accounts/#{accounts(:depository).id}"
    request.script_name = "/api/hassio_ingress/first"
    first_key = sidebar_key

    request.script_name = "/api/hassio_ingress/second"
    assert_not_equal first_key, sidebar_key
  end

  private
    def sidebar_key
      account_sidebar_tabs_cache_key(family: @user.family, active_tab: "all", mobile: false)
    end
end
