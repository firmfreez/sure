# The shape of data expected by `confirm_dialog_controller.js` to override the
# default browser confirm API via Turbo.
class CustomConfirm
  class << self
    def for_resource_deletion(resource_name, high_severity: false)
      resource_label = I18n.t("shared.confirm_dialog.resources.#{resource_name}", default: resource_name.to_s.titleize)
      resource_title = resource_label.to_s
      resource_lower = resource_label.to_s.downcase

      new(
        destructive: true,
        high_severity: high_severity,
        title: I18n.t("shared.confirm_dialog.resource_delete.title", resource: resource_title),
        body: I18n.t("shared.confirm_dialog.resource_delete.body", resource: resource_lower),
        btn_text: I18n.t("shared.confirm_dialog.resource_delete.confirm", resource: resource_title)
      )
    end
  end

  def initialize(title: default_title, body: default_body, btn_text: default_btn_text, destructive: false, high_severity: false)
    @title = title
    @body = body
    @btn_text = btn_text
    @btn_variant = derive_btn_variant(destructive, high_severity)
  end

  def to_data_attribute
    {
      title: title,
      body: body,
      confirmText: btn_text,
      variant: btn_variant
    }
  end

  private
    attr_reader :title, :body, :btn_text, :btn_variant

    def derive_btn_variant(destructive, high_severity)
      return "primary" unless destructive
      high_severity ? "destructive" : "outline-destructive"
    end

    def default_title
      I18n.t("shared.confirm_dialog.title")
    end

    def default_body
      I18n.t("shared.confirm_dialog.body")
    end

    def default_btn_text
      I18n.t("shared.confirm_dialog.confirm")
    end
end
