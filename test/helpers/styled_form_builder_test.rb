require "test_helper"

class StyledFormBuilderTest < ActionView::TestCase
  setup do
    @builder = StyledFormBuilder.new(:account_statement, nil, self, {})
  end

  test "a labelled file field sits in a form field with its label" do
    field = Nokogiri::HTML.fragment(@builder.file_field(:files, label: "Statement files")).at(".form-field")

    assert field, "expected the file input wrapped in a .form-field"
    assert_equal "account_statement_files", field.at("label.form-field__label")["for"]
    assert_includes field.at("input[type=file]")["class"].split, "file:bg-container-inset"
  end

  # The dropzones pass `hidden` and draw their own target: no wrapper, and
  # their classes merged in rather than replaced.
  test "an unlabelled file field comes back bare and keeps the caller's classes" do
    fragment = Nokogiri::HTML.fragment(@builder.file_field(:files, class: "hidden"))

    assert_nil fragment.at(".form-field")
    assert_includes fragment.at("input[type=file]")["class"].split, "hidden"
  end

  test "a new money field leaves the default zero amount empty" do
    account = Account.new(balance: 0, currency: "USD")

    assert_nil money_input(account)["value"]
    assert_nil money_input(nil, value: 0)["value"]
  end

  test "a new money field keeps a prefilled nonzero amount" do
    account = Account.new(balance: 123.45, currency: "USD")

    assert_equal "123.45", money_input(account)["value"]
  end

  test "an existing money field keeps its saved zero amount" do
    account = accounts(:depository)
    account.balance = 0

    assert_equal "0.00", money_input(account)["value"]
  end

  test "a rejected form keeps the submitted zero amount" do
    account = Account.new(balance: 0, currency: "USD")
    account.errors.add(:name, :blank)

    assert_equal "0.00", money_input(account)["value"]
  end

  private
    def money_input(account, **options)
      builder = StyledFormBuilder.new(:account, account, self, {})
      Nokogiri::HTML.fragment(builder.money_field(:balance, **options)).at("[data-money-field-target='amount']")
    end
end
