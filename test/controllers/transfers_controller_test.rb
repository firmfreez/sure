require "test_helper"

class TransfersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "should get new" do
    get new_transfer_url
    assert_response :success
  end

  test "can create transfers" do
    assert_difference "Transfer.count", 1 do
      post transfers_url, params: {
        transfer: {
          from_account_id: accounts(:depository).id,
          to_account_id: accounts(:credit_card).id,
          date: Date.current,
          amount: 100,
          name: "Test Transfer"
        }
      }
      assert_enqueued_with job: SyncJob
    end
  end

  test "create uses localized success notice" do
    users(:family_admin).update!(locale: "ru")

    post transfers_url, params: {
      transfer: {
        from_account_id: accounts(:depository).id,
        to_account_id: accounts(:credit_card).id,
        date: Date.current,
        amount: 100
      }
    }

    assert_equal "Перевод создан", flash[:notice]
  end

  test "create materializes account balances immediately" do
    family = users(:family_admin).family
    source_account = family.accounts.create!(
      name: "Source Checking",
      balance: 1000,
      currency: "USD",
      status: "active",
      accountable: Depository.new
    )
    destination_account = family.accounts.create!(
      name: "Destination Savings",
      balance: 250,
      currency: "USD",
      status: "active",
      accountable: Depository.new
    )

    source_materializer = mock
    destination_materializer = mock

    Balance::Materializer.expects(:new).with(source_account, strategy: :forward).returns(source_materializer)
    Balance::Materializer.expects(:new).with(destination_account, strategy: :forward).returns(destination_materializer)
    source_materializer.expects(:materialize_balances)
    destination_materializer.expects(:materialize_balances)

    post transfers_url, params: {
      transfer: {
        from_account_id: source_account.id,
        to_account_id: destination_account.id,
        date: Date.current,
        amount: 125
      }
    }
  end

  test "turbo_stream create falls back to path when referer is missing" do
    post transfers_url,
         params: {
           transfer: {
             from_account_id: accounts(:depository).id,
             to_account_id: accounts(:credit_card).id,
             date: Date.current,
             amount: 100,
             name: "Turbo transfer"
           }
         },
         headers: { "Accept" => Mime[:turbo_stream].to_s }

    assert_response :success
    assert_equal Mime[:turbo_stream].to_s, response.media_type
    assert_includes response.body, %(turbo-stream action="redirect" target="#{transactions_path}")
  end

  test "destroy deletes transfer and both linked transactions" do
    transfer = transfers(:one)

    assert_difference -> { Transfer.count }, -1 do
      assert_difference -> { Transaction.count }, -2 do
        assert_difference -> { Entry.count }, -2 do
          delete transfer_url(transfer)
        end
      end
    end

    assert_not Transaction.exists?(transfer.inflow_transaction_id)
    assert_not Transaction.exists?(transfer.outflow_transaction_id)
  end

  test "destroy materializes affected account balances immediately" do
    transfer = transfers(:one)
    source_materializer = mock
    destination_materializer = mock

    Balance::Materializer.expects(:new).with(transfer.from_account, strategy: :forward).returns(source_materializer)
    Balance::Materializer.expects(:new).with(transfer.to_account, strategy: :forward).returns(destination_materializer)
    source_materializer.expects(:materialize_balances)
    destination_materializer.expects(:materialize_balances)

    delete transfer_url(transfer)
  end

  test "reject removes transfer but keeps underlying transactions" do
    transfer = transfers(:one)

    assert_difference -> { Transfer.count }, -1 do
      patch transfer_url(transfer), params: {
        transfer: {
          status: "rejected"
        }
      }
    end

    assert Transaction.exists?(transfer.inflow_transaction_id)
    assert Transaction.exists?(transfer.outflow_transaction_id)
  end

  test "can add notes to transfer" do
    transfer = transfers(:one)
    assert_nil transfer.notes

    patch transfer_url(transfer), params: { transfer: { notes: "Test notes" } }

    assert_redirected_to transactions_url
    assert_equal "Transfer updated", flash[:notice]
    assert_equal "Test notes", transfer.reload.notes
  end

  test "handles rejection without FrozenError" do
    transfer = transfers(:one)

    assert_difference "Transfer.count", -1 do
      patch transfer_url(transfer), params: {
        transfer: {
          status: "rejected"
        }
      }
    end

    assert_redirected_to transactions_url
    assert_equal "Transfer updated", flash[:notice]

    # Verify the transfer was actually destroyed
    assert_raises(ActiveRecord::RecordNotFound) do
      transfer.reload
    end

    assert Transaction.exists?(transfer.inflow_transaction_id)
    assert Transaction.exists?(transfer.outflow_transaction_id)
  end
end
