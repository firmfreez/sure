require "test_helper"

class ApplicationCable::HomeAssistantConnectionTest < ActiveSupport::TestCase
  test "HA WebSocket origin is accepted only from the trusted ingress peer" do
    config = ActionCable.server.config
    old_protection = config.disable_request_forgery_protection
    config.disable_request_forgery_protection = false
    [ [ "172.30.32.2", true ], [ "192.168.1.42", false ] ].each do |peer, expected|
      env = {
        "REMOTE_ADDR" => peer,
        "HTTP_X_INGRESS_PATH" => "/api/hassio_ingress/test",
        "HTTP_HOST" => "sure.internal:3000",
        "HTTP_ORIGIN" => "https://ha.example",
        "PATH_INFO" => "/cable",
        "rack.url_scheme" => "http"
      }
      HomeAssistantIngressPrefixer.new(->(request) { request }).call(env)
      connection = ApplicationCable::Connection.new(ActionCable.server, env)
      assert_equal expected, connection.send(:allow_request_origin?)
    end
  ensure
    config.disable_request_forgery_protection = old_protection
  end
end
