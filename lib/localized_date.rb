module LocalizedDate
  # A standalone month uses the nominative in Russian; full dates retain
  # the genitive names used by I18n.l ("9 сентября 2026").
  def self.month_year(date)
    month_names = I18n.t("date.standalone_month_names", default: nil)
    return I18n.l(date, format: :month_year) unless month_names

    I18n.t("date.standalone_month_year", month: month_names.fetch(date.month), year: date.year)
  end
end
