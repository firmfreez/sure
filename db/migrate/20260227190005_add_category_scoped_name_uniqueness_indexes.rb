class AddCategoryScopedNameUniquenessIndexes < ActiveRecord::Migration[7.2]
  def change
    add_index :categories, [ :family_id, :name ],
              unique: true,
              where: "parent_id IS NULL",
              name: "idx_categories_unique_root_name_per_family"

    add_index :categories, [ :family_id, :parent_id, :name ],
              unique: true,
              where: "parent_id IS NOT NULL",
              name: "idx_categories_unique_subcategory_name_per_parent"
  end
end
