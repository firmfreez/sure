class Settings::PreferencesController < ApplicationController
  layout "settings"

  def show
    @user = Current.user
    @breadcrumbs = [
      [ t("breadcrumbs.home", default: "Home"), root_path ],
      [ t("settings.settings_nav.preferences_label"), nil ]
    ]
  end
end
