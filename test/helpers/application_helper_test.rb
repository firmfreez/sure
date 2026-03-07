require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "#title(page_title)" do
    title("Test Title")
    assert_equal "Test Title", content_for(:title)
  end

  test "#header_title(page_title)" do
    header_title("Test Header Title")
    assert_equal "Test Header Title", content_for(:header_title)
  end

  def setup
    @account1 = Account.new(currency: "USD", balance: 1)
    @account2 = Account.new(currency: "USD", balance: 2)
    @account3 = Account.new(currency: "EUR", balance: -7)
  end

  test "#totals_by_currency(collection: collection, money_method: money_method)" do
    assert_equal "$3.00", totals_by_currency(collection: [ @account1, @account2 ], money_method: :balance_money)
    assert_equal "$3.00 | -€7.00", totals_by_currency(collection: [ @account1, @account2, @account3 ], money_method: :balance_money)
    assert_equal "", totals_by_currency(collection: [], money_method: :balance_money)
    assert_equal "$0.00", totals_by_currency(collection: [ Account.new(currency: "USD", balance: 0) ], money_method: :balance_money)
    assert_equal "-$3.00 | €7.00", totals_by_currency(collection: [ @account1, @account2, @account3 ], money_method: :balance_money, negate: true)
  end

  test "#format_month_year handles 1-based month name arrays" do
    month_names = [ nil, "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" ]
    i18n_t = lambda do |key, **|
      key == "date.month_names_standalone" ? month_names : key
    end

    I18n.stub(:t, i18n_t) do
      I18n.stub(:l, "fallback") do
        assert_equal "Jan 2026", format_month_year(Date.new(2026, 1, 15))
      end
    end
  end

  test "#format_month_year handles 0-based month name arrays" do
    month_names = [ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" ]
    i18n_t = lambda do |key, **|
      key == "date.month_names_standalone" ? month_names : key
    end

    I18n.stub(:t, i18n_t) do
      I18n.stub(:l, "fallback") do
        assert_equal "Jan 2026", format_month_year(Date.new(2026, 1, 15))
      end
    end
  end
end
