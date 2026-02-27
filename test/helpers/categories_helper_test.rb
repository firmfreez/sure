require "test_helper"

class CategoriesHelperTest < ActionView::TestCase
  include CategoriesHelper

  test "transfer and payment categories are localized for russian" do
    I18n.with_locale(:ru) do
      assert_equal "Перевод", transfer_category.name
      assert_equal "Платеж", payment_category.name
    end
  end
end
