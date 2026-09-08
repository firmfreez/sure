require "test_helper"
require "open3"

class HaUpgradeAuditTest < ActiveSupport::TestCase
  test "accepts lossless historical column conversions and additions" do
    before = { categories: [ { id: "category", classification: "expense" } ], addresses: [ { id: "address", postal_code: 12345 } ] }
    after = { categories: [ { id: "category", classification_unused: "expense", last_used_at: nil } ], addresses: [ { id: "address", postal_code: "12345" } ] }
    output, status = compare(before, after)
    assert status.success?, output
  end

  test "rejects removed IDs and changed financial amounts without exposing values" do
    before = { entries: [ { id: "one", amount: "123.45" }, { id: "two", amount: "67.89" } ] }
    after = { entries: [ { id: "one", amount: "0.00" } ] }
    output, status = compare(before, after)
    assert_not status.success?
    assert_includes output, "1 missing IDs"
    assert_includes output, "amount"
    assert_not_includes output, "123.45"
  end

  private
    def compare(before, after)
      Tempfile.create do |original|
        Tempfile.create do |updated|
          original.write(JSON.generate(before))
          updated.write(JSON.generate(after))
          original.flush
          updated.flush
          Open3.capture2e(RbConfig.ruby, Rails.root.join("script/ha_upgrade_audit.rb").to_s, "compare", original.path, updated.path)
        end
      end
    end
end
