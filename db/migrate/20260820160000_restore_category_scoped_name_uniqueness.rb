class RestoreCategoryScopedNameUniqueness < ActiveRecord::Migration[7.2]
  def change
    remove_index :categories, name: "index_categories_on_family_id_and_name", if_exists: true

    add_index :categories, [ :family_id, :name ],
              unique: true,
              where: "parent_id IS NULL",
              name: "idx_categories_unique_root_name_per_family",
              if_not_exists: true

    add_index :categories, [ :family_id, :parent_id, :name ],
              unique: true,
              where: "parent_id IS NOT NULL",
              name: "idx_categories_unique_subcategory_name_per_parent",
              if_not_exists: true
  end
end
