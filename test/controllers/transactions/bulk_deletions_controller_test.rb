require "test_helper"

class Transactions::BulkDeletionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @entry = entries(:transaction)
  end

  test "bulk deletion preserves both sides when the other account is read only" do
    sign_in users(:family_member)

    assert_no_difference [ "Transfer.count", "Entry.count", "Transaction.count" ] do
      post transactions_bulk_deletion_url, params: { bulk_delete: { entry_ids: [ entries(:transfer_out).id ] } }
    end
  end

  test "bulk deleting one side deletes the complete transfer" do
    assert_difference "Transfer.count", -1 do
      assert_difference [ "Entry.count", "Transaction.count" ], -2 do
        post transactions_bulk_deletion_url, params: { bulk_delete: { entry_ids: [ entries(:transfer_in).id ] } }
      end
    end
  end

  test "bulk delete" do
    transactions = @user.family.entries.transactions
    delete_count = transactions.size

    assert_difference([ "Transaction.count", "Entry.count" ], -delete_count) do
      post transactions_bulk_deletion_url, params: {
        bulk_delete: {
          entry_ids: transactions.pluck(:id)
        }
      }
    end

    assert_redirected_to transactions_url
    assert_equal "#{delete_count} transactions deleted", flash[:notice]
  end

  test "bulk delete with rejected transfers" do
    entry = entries(:transaction)
    other_entry = entries(:transfer_out)

    # Create a rejected_transfer referencing the entry's transaction
    RejectedTransfer.create!(
      inflow_transaction: entry.entryable,
      outflow_transaction: other_entry.entryable
    )

    assert_difference "RejectedTransfer.count", -1 do
      assert_difference [ "Transaction.count", "Entry.count" ], -1 do
        post transactions_bulk_deletion_url, params: {
          bulk_delete: {
            entry_ids: [ entry.id ]
          }
        }
      end
    end

    assert_redirected_to transactions_url
    assert_equal "1 transaction deleted", flash[:notice]
  end
end
