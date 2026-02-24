module Onboardable
  extend ActiveSupport::Concern

  included do
    before_action :require_onboarding_and_upgrade
  end

  private
    # First, we require onboarding, then once that's complete, we require an upgrade for non-subscribed users.
    def require_onboarding_and_upgrade
      return unless Current.user
      return unless redirectable_path?(request.path)

      if Current.user.needs_onboarding?
        redirect_to onboarding_path
      elsif Current.family.needs_subscription?
        redirect_to trial_onboarding_path
      elsif Current.family.upgrade_required?
        redirect_to upgrade_subscription_path
      end
    end

    def redirectable_path?(path)
      normalized = normalize_path_for_redirect(path)

      return false if normalized.starts_with?("/settings")
      return false if normalized.starts_with?("/subscription")
      return false if normalized.starts_with?("/onboarding")
      return false if normalized.starts_with?("/users")
      return false if normalized.starts_with?("/api")  # Exclude API endpoints from onboarding redirects

      [
        new_registration_path,
        new_session_path,
        new_password_reset_path,
        new_email_confirmation_path
      ].exclude?(normalized)
    end

    def normalize_path_for_redirect(path)
      normalized = path.to_s
      script_name = request.script_name.to_s

      if script_name.present? && normalized.start_with?(script_name)
        normalized = normalized.delete_prefix(script_name)
        normalized = "/#{normalized}" unless normalized.start_with?("/")
      end

      normalized
    end
end
