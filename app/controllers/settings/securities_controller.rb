class Settings::SecuritiesController < ApplicationController
  layout "settings"

  def show
    @breadcrumbs = [
      [ t("breadcrumbs.home", default: "Home"), root_path ],
      [ t("settings.settings_nav.security_label"), nil ]
    ]
    @oidc_identities = Current.user.oidc_identities.order(:provider)
  end
end
