require "test_helper"
require Rails.root.join("db/migrate/20260727115959_merge_duplicate_tag_and_category_names")

class HomeAssistantCategoryPreservationTest < ActiveSupport::TestCase
  test "upstream deduplication version preserves distinct HA category IDs and references" do
    family = families(:dylan_family)
    first_parent = categories(:food_and_drink)
    second_parent = categories(:income)
    first = family.categories.create!(name: "Shared child", parent: first_parent, color: first_parent.color)
    second = family.categories.create!(name: "Shared child", parent: second_parent, color: second_parent.color)
    transaction = transactions(:one)
    transaction.update!(category: second)
    before = Category.order(:id).pluck(:id, :name, :parent_id)

    MergeDuplicateTagAndCategoryNames.new.migrate(:up)

    assert_equal before, Category.order(:id).pluck(:id, :name, :parent_id)
    assert_equal second.id, transaction.reload.category_id
    assert_not_equal first.id, second.id
    duplicate = second.dup
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:name, :taken)
  end
end
