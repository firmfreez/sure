class Valuation::Name
  def initialize(valuation_kind, accountable_type)
    @valuation_kind = valuation_kind
    @accountable_type = accountable_type
  end

  def to_s
    case valuation_kind
    when "opening_anchor"
      opening_anchor_name
    when "current_anchor"
      current_anchor_name
    else
      recon_name
    end
  end

  private
    attr_reader :valuation_kind, :accountable_type

    def opening_anchor_name
      I18n.t(
        "models.valuation.names.opening_anchor.#{accountable_type_key}",
        default: I18n.t("models.valuation.names.opening_anchor.default", default: "Opening balance")
      )
    end

    def current_anchor_name
      I18n.t(
        "models.valuation.names.current_anchor.#{accountable_type_key}",
        default: I18n.t("models.valuation.names.current_anchor.default", default: "Current balance")
      )
    end

    def recon_name
      I18n.t(
        "models.valuation.names.recon.#{accountable_type_key}",
        default: I18n.t("models.valuation.names.recon.default", default: "Manual balance update")
      )
    end

    def accountable_type_key
      case accountable_type
      when "Property", "Vehicle"
        "property"
      when "Loan"
        "loan"
      when "Investment", "Crypto", "OtherAsset"
        "investment"
      else
        "default"
      end
    end
end
