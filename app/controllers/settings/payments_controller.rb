class Settings::PaymentsController < ApplicationController
  layout "settings"

  guard_feature unless: -> { Current.family.can_manage_subscription? }

  def show
    @family = Current.family
    @breadcrumbs = [
      [ t("breadcrumbs.home", default: "Home"), root_path ],
      [ t("settings.settings_nav.payment_label"), nil ]
    ]
  end
end
