module Breadcrumbable
  extend ActiveSupport::Concern

  included do
    before_action :set_breadcrumbs
  end

  private
    def breadcrumb_t(key, **options)
      I18n.t(key, locale: resolved_locale, **options)
    end

    # The default, unless specific controller or action explicitly overrides
    def set_breadcrumbs
      I18n.with_locale(resolved_locale) do
        @breadcrumbs = [
          [ breadcrumb_t("breadcrumbs.home", default: "Home"), root_path ],
          [ breadcrumb_t("breadcrumbs.#{controller_name}", default: controller_name.titleize), nil ]
        ]
      end
    end
end
