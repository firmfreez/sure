require "test_helper"

class HomeAssistantIngressPrefixerTest < ActiveSupport::TestCase
  test "prefixes stripped and unstripped paths without duplicating the mount" do
    [ "/accounts", "/api/hassio_ingress/test/accounts" ].each do |path|
      env = { "REMOTE_ADDR" => "172.30.32.2", "HTTP_X_INGRESS_PATH" => "/api/hassio_ingress/test/", "PATH_INFO" => path }
      HomeAssistantIngressPrefixer.new(->(request) { request }).call(env)
      assert_equal "/api/hassio_ingress/test", env["SCRIPT_NAME"]
      assert_equal "/accounts", env["PATH_INFO"]
      assert env["sure.trusted_ha_ingress"]
    end
  end

  test "forwarded client addresses cannot authenticate direct traffic" do
    env = { "REMOTE_ADDR" => "192.168.1.42", "HTTP_X_FORWARDED_FOR" => "172.30.32.2", "HTTP_X_INGRESS_PATH" => "/api/hassio_ingress/test", "PATH_INFO" => "/accounts" }
    HomeAssistantIngressPrefixer.new(->(request) { request }).call(env)
    assert_not env["sure.trusted_ha_ingress"]
  end

  test "rejects unsafe prefixes and respects path segment boundaries" do
    [ "//evil.example", "/prefix?query", "/prefix/../other" ].each do |prefix|
      env = { "HTTP_X_INGRESS_PATH" => prefix, "PATH_INFO" => "/accounts" }
      HomeAssistantIngressPrefixer.new(->(request) { request }).call(env)
      assert_nil env["SCRIPT_NAME"]
    end
    env = { "HTTP_X_INGRESS_PATH" => "/prefix", "PATH_INFO" => "/prefix-other/accounts" }
    HomeAssistantIngressPrefixer.new(->(request) { request }).call(env)
    assert_equal "/prefix-other/accounts", env["PATH_INFO"]
  end
end
