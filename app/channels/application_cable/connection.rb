module ApplicationCable
  class Connection < ActionCable::Connection::Base
    rescue_from StandardError, with: :report_error

    private
      def allow_request_origin?
        return true if env["sure.trusted_ha_ingress"]

        super
      end

      def report_error(e)
        Sentry.capture_exception(e)
      end
  end
end
