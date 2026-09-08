require "test_helper"

class TransactionsHelperTest < ActionView::TestCase
  setup do
    transactions(:transfer_out).update!(kind: "cc_payment")
    transactions(:transfer_in).update!(kind: "cc_payment")
  end

  test "localizes stored transfer and payment names in both directions" do
    transfer = transfers(:one)

    I18n.with_locale(:ru) do
      { "Transfer" => "Перевод", "Payment" => "Платеж" }.each do |prefix, label|
        outflow = transfer.outflow_transaction.entry
        outflow.name = "#{prefix} to #{transfer.to_account.name}"
        assert_equal "#{label} на #{transfer.to_account.name}", transaction_display_name(outflow)

        inflow = transfer.inflow_transaction.entry
        inflow.name = "#{prefix} from #{transfer.from_account.name}"
        assert_equal "#{label} со счета #{transfer.from_account.name}", transaction_display_name(inflow)
      end
    end
  end

  test "preserves custom transfer names and ordinary transaction names" do
    I18n.with_locale(:ru) do
      entry = transfers(:one).outflow_transaction.entry
      entry.name = "На общие расходы"
      assert_equal entry.name, transaction_display_name(entry)

      entry = transactions(:one).entry
      entry.name = "Transfer to Savings"
      assert_equal entry.name, transaction_display_name(entry)
    end
  end
end
