module ImportsHelper
  def mapping_label(mapping_class)
    key = {
      "Import::AccountTypeMapping" => "account_type",
      "Import::AccountMapping" => "account",
      "Import::CategoryMapping" => "category",
      "Import::TagMapping" => "tag"
    }.fetch(mapping_class.name)

    I18n.t("imports.mappings.labels.#{key}")
  end

  def import_col_label(key)
    I18n.t("imports.columns.#{key}", default: key.to_s.humanize)
  end

  def dry_run_resource(key)
    map = {
      transactions: DryRunResource.new(label: I18n.t("imports.dry_run.transactions"), icon: "credit-card", text_class: "text-cyan-500", bg_class: "bg-cyan-500/5"),
      accounts: DryRunResource.new(label: I18n.t("imports.dry_run.accounts"), icon: "layers", text_class: "text-orange-500", bg_class: "bg-orange-500/5"),
      categories: DryRunResource.new(label: I18n.t("imports.dry_run.categories"), icon: "shapes", text_class: "text-blue-500", bg_class: "bg-blue-500/5"),
      tags: DryRunResource.new(label: I18n.t("imports.dry_run.tags"), icon: "tags", text_class: "text-violet-500", bg_class: "bg-violet-500/5"),
      rules: DryRunResource.new(label: I18n.t("imports.dry_run.rules"), icon: "workflow", text_class: "text-green-500", bg_class: "bg-green-500/5")
    }

    map[key]
  end

  def import_type_label(import_type)
    key = import_type.to_s.underscore
    I18n.t("imports.types.#{key}", default: import_type.to_s.titleize.gsub(/ Import\z/, ""))
  end

  def permitted_import_configuration_path(import)
    if permitted_import_types.include?(import.type.underscore)
      "import/configurations/#{import.type.underscore}"
    else
      raise "Unknown import type: #{import.type}"
    end
  end

  def cell_class(row, field)
    base = "bg-container text-sm focus:ring-gray-900 theme-dark:focus:ring-gray-100 focus:border-solid w-full max-w-full disabled:text-subdued"

    row.valid? # populate errors

    border = row.errors.key?(field) ? "border-destructive" : "border-transparent"

    [ base, border ].join(" ")
  end

  def cell_is_valid?(row, field)
    row.valid? # populate errors
    !row.errors.key?(field)
  end

  private
    def permitted_import_types
      %w[transaction_import trade_import account_import mint_import category_import rule_import]
    end

    DryRunResource = Struct.new(:label, :icon, :text_class, :bg_class, keyword_init: true)
end
