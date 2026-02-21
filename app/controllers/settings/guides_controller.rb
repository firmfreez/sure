class Settings::GuidesController < ApplicationController
  layout "settings"

  def show
    @breadcrumbs = [
      [ t("breadcrumbs.home", default: "Home"), root_path ],
      [ t("settings.settings_nav.guides_label"), nil ]
    ]
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      superscript: true
    )
    localized_path = Rails.root.join("docs/onboarding/guide.#{I18n.locale}.md")
    fallback_path = Rails.root.join("docs/onboarding/guide.md")
    path = File.exist?(localized_path) ? localized_path : fallback_path
    @guide_content = markdown.render(File.read(path))
  end
end
