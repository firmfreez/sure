require "test_helper"

class LocalizedDateTest < ActiveSupport::TestCase
  test "Russian month headings use nominative while full dates use genitive" do
    I18n.with_locale(:ru) do
      assert_equal "Сентябрь 2026", LocalizedDate.month_year(Date.new(2026, 9, 9))
      assert_equal "Январь 2026", LocalizedDate.month_year(Date.new(2026, 1, 1))
      assert_equal "9 сентября 2026", I18n.l(Date.new(2026, 9, 9), format: :long)
      assert_equal [ "сент.", "нояб.", "дек." ], I18n.t("date.abbr_month_names").values_at(9, 11, 12)
    end
  end

  test "other locales retain their month year format" do
    I18n.with_locale(:en) do
      assert_equal "September 2026", LocalizedDate.month_year(Date.new(2026, 9, 9))
    end
  end
end
