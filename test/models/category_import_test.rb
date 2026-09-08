require "test_helper"

class CategoryImportTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @csv = <<~CSV
      name,color,parent_category,icon
      Food & Drink,#f97316,,carrot
      Groceries,#407706,Food & Drink,shopping-basket
      Salary,#22c55e,,briefcase
    CSV
  end

  test "round trip preserves same-name categories under different parents and their transactions" do
    first_parent = categories(:food_and_drink)
    second_parent = categories(:income)
    first = @family.categories.create!(name: "Shared import name", parent: first_parent, color: first_parent.color)
    second = @family.categories.create!(name: "Shared import name", parent: second_parent, color: second_parent.color)
    transactions(:one).update!(category: second)
    csv = CSV.generate do |output|
      output << %w[name color parent_category icon]
      [ first, second ].each { |category| output << [ category.name, category.color, category.parent.name, category.lucide_icon ] }
    end
    import = @family.imports.create!(type: "CategoryImport", raw_file_str: csv, col_sep: ",")
    import.generate_rows_from_csv
    assert_no_difference "Category.count" do
      import.import!
    end
    assert_equal first_parent.id, first.reload.parent_id
    assert_equal second_parent.id, second.reload.parent_id
    assert_equal second.id, transactions(:one).reload.category_id
  end

  test "imports categories from Sure export" do
    import = @family.imports.create!(type: "CategoryImport", raw_file_str: @csv, col_sep: ",")
    import.generate_rows_from_csv
    assert_equal 3, import.rows.count

    tracked_categories = Category.where(family: @family, name: [ "Food & Drink", "Groceries", "Salary" ])

    assert_difference -> { tracked_categories.count }, 2 do
      import.send(:import!)
    end

    food = Category.find_by!(family: @family, name: "Food & Drink")
    groceries = Category.find_by!(family: @family, name: "Groceries")
    salary = Category.find_by!(family: @family, name: "Salary")

    assert_equal "carrot", food.lucide_icon
    assert_equal food, groceries.parent
    assert_equal "shopping-basket", groceries.lucide_icon
    assert_equal "briefcase", salary.lucide_icon
  end

  test "imports subcategories even when parent row comes later" do
    csv = <<~CSV
      name,color,parent_category,icon
      Utilities,#407706,Household,plug
      Household,#f97316,,house
    CSV

    import = @family.imports.create!(type: "CategoryImport", raw_file_str: csv, col_sep: ",")
    import.generate_rows_from_csv

    import.send(:import!)

    household = Category.find_by!(family: @family, name: "Household")
    utilities = Category.find_by!(family: @family, name: "Utilities")

    assert_equal household, utilities.parent
    assert_equal "#f97316", household.color
  end

  test "updates categories when duplicate rows are provided" do
    csv = <<~CSV
      name,color,parent_category,icon
      Snacks,#aaaaaa,,cookie
      Snacks,#bbbbbb,,pizza
    CSV

    import = @family.imports.create!(type: "CategoryImport", raw_file_str: csv, col_sep: ",")
    import.generate_rows_from_csv

    import.send(:import!)

    snacks = Category.find_by!(family: @family, name: "Snacks")
    assert_equal "#bbbbbb", snacks.color
    assert_equal "pizza", snacks.lucide_icon
  end

  test "accepts required headers with an asterisk suffix" do
    csv = <<~CSV
      name*,color,parent_category,icon
      Food & Drink,#f97316,,carrot
    CSV

    import = @family.imports.create!(type: "CategoryImport", raw_file_str: csv, col_sep: ",")
    import.generate_rows_from_csv

    assert_equal 1, import.rows.count
    assert_equal "Food & Drink", import.rows.first.name
  end

  test "fails fast when required headers are missing" do
    csv = <<~CSV
      title,color,parent_category,icon
      Food & Drink,#f97316,,carrot
    CSV

    import = @family.imports.create!(type: "CategoryImport", raw_file_str: csv, col_sep: ",")

    error = assert_raises(ActiveRecord::RecordInvalid) { import.generate_rows_from_csv }
    assert_includes error.message, "Missing required columns: name"
  end
end
