require "test_helper"

class HomeAssistantIngressTest < ActionDispatch::IntegrationTest
  setup do
    @old_auto_login = ENV["HA_INGRESS_AUTO_LOGIN"]
    ENV["HA_INGRESS_AUTO_LOGIN"] = "true"
    Rails.application.config.app_mode.stubs(:self_hosted?).returns(true)
    Redis.any_instance.stubs(:ping).returns("PONG")
    @user = users(:family_admin)
    @identity = OidcIdentity.create!(user: @user, provider: Authentication::HOME_ASSISTANT_PROVIDER, uid: "ha-existing-user")
    @headers = {
      "REMOTE_ADDR" => "172.30.32.2",
      "X-Ingress-Path" => "/api/hassio_ingress/test",
      "X-Remote-User-Id" => @identity.uid,
      "X-Remote-User-Display-Name" => "Иван Иванов"
    }
  end

  teardown do
    ENV["HA_INGRESS_AUTO_LOGIN"] = @old_auto_login
  end

  test "existing HA identity keeps user family and UUID and receives a session" do
    original = @user.attributes.slice("id", "family_id", "email", "first_name", "last_name")
    assert_no_difference [ "User.count", "Family.count", "OidcIdentity.count" ] do
      assert_difference "Session.count", 1 do
        get accounts_url, headers: @headers
      end
    end
    assert_equal original, @user.reload.attributes.slice(*original.keys)
    assert_equal @user.id, Session.order(:created_at).last.user_id
    assert cookies[:session_token].present?
    assert_response :success
    assert_select "meta[name=action-cable-url][content=?]", "/api/hassio_ingress/test/cable"
    assert_select "link[rel=stylesheet]" do |links|
      assert links.all? { |link| link["href"].start_with?("/api/hassio_ingress/test/") }
    end
    assert_select "script[type=importmap]" do |maps|
      imports = JSON.parse(maps.first.content).fetch("imports")
      assert imports.fetch("application").start_with?("/api/hassio_ingress/test/")
    end
  end

  test "trusted ingress still requires a CSRF token for writes" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get accounts_url, headers: @headers
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')["content"]
    patch user_url(@user), params: { user: { show_sidebar: false } }, headers: @headers.merge("Origin" => "http://homeassistant.local:8123")
    assert_response :unprocessable_entity
    assert @user.reload.show_sidebar?
    patch user_url(@user), params: { user: { show_sidebar: false } }, headers: @headers.merge("Origin" => "http://homeassistant.local:8123", "X-CSRF-Token" => token)
    assert_not @user.reload.show_sidebar?
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  test "direct port cannot use spoofed HA identity headers" do
    assert_no_difference "Session.count" do
      get accounts_url, headers: @headers.merge("REMOTE_ADDR" => "192.168.1.42", "X-Forwarded-For" => "172.30.32.2")
    end
    assert_response :redirect
    assert_match %r{/api/hassio_ingress/test/sessions/new}, response.location
  end

  test "disabled auto login and inactive users cannot receive a session" do
    ENV["HA_INGRESS_AUTO_LOGIN"] = "false"
    assert_no_difference "Session.count" do
      get accounts_url, headers: @headers
    end
    ENV["HA_INGRESS_AUTO_LOGIN"] = "true"
    @user.update_column(:active, false)
    assert_no_difference "Session.count" do
      get accounts_url, headers: @headers
    end
  end

  test "removed SSO identities are not automatically provisioned again" do
    SsoIdentityBlock.block_all!(OidcIdentity.where(id: @identity.id), identity_label: "Removed HA user")
    @identity.destroy!
    assert_no_difference [ "Session.count", "User.count", "OidcIdentity.count" ] do
      get accounts_url, headers: @headers
    end
  end
end
