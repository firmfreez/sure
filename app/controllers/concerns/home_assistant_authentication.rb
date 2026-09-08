module HomeAssistantAuthentication
  extend ActiveSupport::Concern

  PROVIDER = "home_assistant_ingress"

  private
    def find_or_create_home_assistant_session
      return unless home_assistant_ingress_login_enabled?

      remote_user_id = normalized_header_value("X-Remote-User-Id")
      return if remote_user_id.blank?

      SsoIdentityBlock.with_identity_lock(provider: PROVIDER, uid: remote_user_id) do
        next if SsoIdentityBlock.blocked?(provider: PROVIDER, uid: remote_user_id)

        identity = OidcIdentity.find_by(provider: PROVIDER, uid: remote_user_id)
        user = identity&.user || provision_home_assistant_user!(remote_user_id)
        next unless user&.active?

        upsert_home_assistant_identity!(user, remote_user_id)
        create_session_for(user)
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[HA] Failed to authenticate ingress user: #{e.class} - #{e.message}")
      nil
    end

    def home_assistant_ingress_login_enabled?
      return false unless Rails.application.config.app_mode.self_hosted?
      return false unless request.env["sure.trusted_ha_ingress"]

      ActiveModel::Type::Boolean.new.cast(ENV["HA_INGRESS_AUTO_LOGIN"])
    end

    def provision_home_assistant_user!(remote_user_id)
      username = normalized_header_value("X-Remote-User-Name").presence
      display_name = normalized_header_value("X-Remote-User-Display-Name").presence
      first_name, last_name = split_name(display_name || username)

      email = home_assistant_email_for(remote_user_id)
      if (existing_user = User.find_by(email: email))
        return existing_user
      end

      family = home_assistant_family
      user = User.new(
        family: family,
        email: email,
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

      user.update!(first_name: user.first_name.presence || first_name, last_name: user.last_name.presence || last_name)

      identity = OidcIdentity.find_or_initialize_by(provider: PROVIDER, uid: remote_user_id)
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
end
