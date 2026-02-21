module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :set_request_details
    before_action :authenticate_user!
    before_action :set_sentry_user
  end

  class_methods do
    def skip_authentication(**options)
      skip_before_action :authenticate_user!, **options
      skip_before_action :set_sentry_user, **options
    end
  end

  private
    def authenticate_user!
      if session_record = find_session_by_cookie
        Current.session = session_record
      else
        if self_hosted_first_login?
          redirect_to new_registration_url
        else
          redirect_to new_session_url
        end
      end
    end

    def find_session_by_cookie
      cookie_value = cookies.signed[:session_token]

      if cookie_value.present?
        Session.find_by(id: cookie_value)
      else
        nil
      end
    end

    def create_session_for(user)
      session = user.sessions.create!
      cookies.signed.permanent[:session_token] = { value: session.id, httponly: true }
      session
    end

    def self_hosted_first_login?
      Rails.application.config.app_mode.self_hosted? && User.count.zero?
    end

    def find_or_create_home_assistant_session
      return unless home_assistant_ingress_login_enabled?

      remote_user_id = normalized_header_value("X-Remote-User-Id")
      return if remote_user_id.blank?

      identity = OidcIdentity.find_by(provider: HOME_ASSISTANT_PROVIDER, uid: remote_user_id)
      user = identity&.user || provision_home_assistant_user!(remote_user_id)
      return unless user&.active?

      upsert_home_assistant_identity!(user, remote_user_id)
      create_session_for(user)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[HA] Failed to authenticate ingress user: #{e.class} - #{e.message}")
      nil
    end

    def home_assistant_ingress_login_enabled?
      return false unless Rails.application.config.app_mode.self_hosted?

      ActiveModel::Type::Boolean.new.cast(ENV["HA_INGRESS_AUTO_LOGIN"])
    end

    def provision_home_assistant_user!(remote_user_id)
      username = normalized_header_value("X-Remote-User-Name").presence
      display_name = normalized_header_value("X-Remote-User-Display-Name").presence
      first_name, last_name = split_name(display_name || username)

      family = home_assistant_family
      user = User.new(
        family: family,
        email: home_assistant_email_for(remote_user_id),
        first_name: first_name,
        last_name: last_name,
        role: User.role_for_new_family_creator
      )
      user.password = SecureRandom.base58(32)
      user.save!
      user
    end

    def upsert_home_assistant_identity!(user, remote_user_id)
      username = normalized_header_value("X-Remote-User-Name").presence
      display_name = normalized_header_value("X-Remote-User-Display-Name").presence
      first_name, last_name = split_name(display_name || username)

      user.update!(first_name: first_name, last_name: last_name) if first_name.present? || last_name.present?

      identity = OidcIdentity.find_or_initialize_by(provider: HOME_ASSISTANT_PROVIDER, uid: remote_user_id)
      identity.user = user
      identity.info = {
        username: username,
        display_name: display_name
      }.compact
      identity.last_authenticated_at = Time.current
      identity.save!
      identity
    end

    def home_assistant_email_for(remote_user_id)
      domain = ENV.fetch("HA_INGRESS_EMAIL_DOMAIN", "home-assistant.local")
      digest = Digest::SHA256.hexdigest(remote_user_id)[0, 24]
      "ha-#{digest}@#{domain}"
    end

    def home_assistant_family
      Family.find_or_create_by!(name: "Семья")
    end

    def split_name(raw_name)
      return [ nil, nil ] if raw_name.blank?

      parts = raw_name.split(/\s+/, 2)
      [ parts[0], parts[1] ]
    end

    # Rack headers can arrive as ASCII-8BIT while carrying UTF-8 bytes.
    # Normalize early so persistence/rendering/json serialization stay safe.
    def normalized_header_value(header_name)
      value = request.headers[header_name].to_s
      return "" if value.empty?

      value
        .dup
        .force_encoding(Encoding::UTF_8)
        .scrub
        .strip
    rescue Encoding::CompatibilityError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace).strip
    end
    def set_request_details
      Current.user_agent = request.user_agent
      Current.ip_address = request.ip
    end

    def set_sentry_user
      return unless defined?(Sentry) && ENV["SENTRY_DSN"].present?

      if Current.user
        Sentry.set_user(
          id: Current.user.id,
          email: Current.user.email,
          username: Current.user.display_name,
          ip_address: Current.ip_address
        )
      end
    end
end
