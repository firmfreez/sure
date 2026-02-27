require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  def setup
    @family = families(:dylan_family)
  end

  test "replacing and destroying" do
    transactions = categories(:food_and_drink).transactions.to_a

    categories(:food_and_drink).replace_and_destroy!(categories(:income))

    assert_equal categories(:income), transactions.map { |t| t.reload.category }.uniq.first
  end

  test "replacing with nil should nullify the category" do
    transactions = categories(:food_and_drink).transactions.to_a

    categories(:food_and_drink).replace_and_destroy!(nil)

    assert_nil transactions.map { |t| t.reload.category }.uniq.first
  end

  test "subcategory can only be one level deep" do
    category = categories(:subcategory)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      category.subcategories.create!(name: "Invalid category", family: @family)
    end

    assert_equal "Validation failed: Parent can't have more than 2 levels of subcategories", error.message
  end

  test "all_investment_contributions_names returns all locale variants" do
    names = Category.all_investment_contributions_names

    assert_includes names, "Investment Contributions"  # English
    assert_includes names, "Contributions aux investissements"  # French
    assert_includes names, "Investeringsbijdragen"  # Dutch
    assert names.all? { |name| name.is_a?(String) }
    assert_equal names, names.uniq  # No duplicates
  end

  test "allows same subcategory name under different parents" do
    parent_one = @family.categories.create!(
      name: "Gifts",
      color: "#61c9ea",
      classification: "expense",
      lucide_icon: "gift"
    )
    parent_two = @family.categories.create!(
      name: "Holidays",
      color: "#61c9ea",
      classification: "expense",
      lucide_icon: "party-popper"
    )

    first = @family.categories.create!(
      name: "Birthday",
      color: "#61c9ea",
      classification: "expense",
      lucide_icon: "cake",
      parent: parent_one
    )

    second = @family.categories.new(
      name: "Birthday",
      color: "#61c9ea",
      classification: "expense",
      lucide_icon: "cake",
      parent: parent_two
    )

    assert second.valid?
    assert second.save
    assert_not_equal first.parent_id, second.parent_id
  end

  test "does not allow same subcategory name under same parent" do
    parent = @family.categories.create!(
      name: "Gifts",
      color: "#61c9ea",
      classification: "expense",
      lucide_icon: "gift"
    )

    @family.categories.create!(
      name: "Birthday",
      color: "#61c9ea",
      classification: "expense",
      lucide_icon: "cake",
      parent: parent
    )

    duplicate = @family.categories.new(
      name: "Birthday",
      color: "#61c9ea",
      classification: "expense",
      lucide_icon: "cake",
      parent: parent
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end
end
