# This version is retained from upstream so existing migration ledgers remain valid.
# HA allows the same category name under different parents. Never merge those IDs.
class MergeDuplicateTagAndCategoryNames < ActiveRecord::Migration[7.2]
  def up
    { tags: "family_id, name", categories: "family_id, parent_id, name" }.each do |table, scope|
      duplicates = select_value("SELECT COUNT(*) FROM (SELECT 1 FROM #{table} GROUP BY #{scope} HAVING COUNT(*) > 1) duplicates").to_i
      if duplicates.positive?
        raise ActiveRecord::MigrationError, "#{table}: #{duplicates} duplicate groups within the uniqueness scope. Resolve explicitly after backup; no records have been merged or deleted."
      end
    end
  end

  def down
  end
end
