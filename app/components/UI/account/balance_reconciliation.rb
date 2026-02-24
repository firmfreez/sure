class UI::Account::BalanceReconciliation < ApplicationComponent
  attr_reader :balance, :account

  def initialize(balance:, account:)
    @balance = balance
    @account = account
  end

  def reconciliation_items
    case account.accountable_type
    when "Depository", "OtherAsset", "OtherLiability"
      default_items
    when "CreditCard"
      credit_card_items
    when "Investment"
      investment_items
    when "Loan"
      loan_items
    when "Property", "Vehicle"
      asset_items
    when "Crypto"
      crypto_items
    else
      default_items
    end
  end

  private
    def t_recon(key)
      I18n.t("accounts.show.reconciliation.#{key}", default: key.to_s.humanize)
    end

    def default_items
      items = [
        { label: t_recon("start_balance_label"), value: balance.start_balance_money, tooltip: t_recon("start_balance_tooltip"), style: :start },
        { label: t_recon("net_cash_flow_label"), value: net_cash_flow, tooltip: t_recon("net_cash_flow_tooltip"), style: :flow }
      ]

      if has_adjustments?
        items << { label: t_recon("end_balance_label"), value: end_balance_before_adjustments, tooltip: t_recon("end_balance_tooltip"), style: :subtotal }
        items << { label: t_recon("adjustments_label"), value: total_adjustments, tooltip: t_recon("adjustments_tooltip"), style: :adjustment }
      end

      items << { label: t_recon("final_balance_label"), value: balance.end_balance_money, tooltip: t_recon("final_balance_tooltip"), style: :final }
      items
    end

    def credit_card_items
      items = [
        { label: t_recon("start_balance_label"), value: balance.start_balance_money, tooltip: t_recon("cc_start_balance_tooltip"), style: :start },
        { label: t_recon("cc_charges_label"), value: balance.cash_outflows_money, tooltip: t_recon("cc_charges_tooltip"), style: :flow },
        { label: t_recon("cc_payments_label"), value: balance.cash_inflows_money * -1, tooltip: t_recon("cc_payments_tooltip"), style: :flow }
      ]

      if has_adjustments?
        items << { label: t_recon("end_balance_label"), value: end_balance_before_adjustments, tooltip: t_recon("end_balance_tooltip"), style: :subtotal }
        items << { label: t_recon("adjustments_label"), value: total_adjustments, tooltip: t_recon("adjustments_tooltip"), style: :adjustment }
      end

      items << { label: t_recon("final_balance_label"), value: balance.end_balance_money, tooltip: t_recon("cc_final_balance_tooltip"), style: :final }
      items
    end

    def investment_items
      items = [
        { label: t_recon("start_balance_label"), value: balance.start_balance_money, tooltip: t_recon("investment_start_balance_tooltip"), style: :start }
      ]

      # Change in brokerage cash (includes deposits, withdrawals, and cash from trades)
      items << { label: t_recon("investment_brokerage_cash_label"), value: net_cash_flow, tooltip: t_recon("investment_brokerage_cash_tooltip"), style: :flow }

      # Change in holdings from trading activity
      items << { label: t_recon("investment_holdings_trades_label"), value: net_non_cash_flow, tooltip: t_recon("investment_holdings_trades_tooltip"), style: :flow }

      # Market price changes
      items << { label: t_recon("investment_holdings_market_label"), value: balance.net_market_flows_money, tooltip: t_recon("investment_holdings_market_tooltip"), style: :flow }

      if has_adjustments?
        items << { label: t_recon("end_balance_label"), value: end_balance_before_adjustments, tooltip: t_recon("investment_end_balance_tooltip"), style: :subtotal }
        items << { label: t_recon("adjustments_label"), value: total_adjustments, tooltip: t_recon("adjustments_tooltip"), style: :adjustment }
      end

      items << { label: t_recon("final_balance_label"), value: balance.end_balance_money, tooltip: t_recon("investment_final_balance_tooltip"), style: :final }
      items
    end

    def loan_items
      items = [
        { label: t_recon("loan_start_principal_label"), value: balance.start_balance_money, tooltip: t_recon("loan_start_principal_tooltip"), style: :start },
        { label: t_recon("loan_net_principal_change_label"), value: net_non_cash_flow, tooltip: t_recon("loan_net_principal_change_tooltip"), style: :flow }
      ]

      if has_adjustments?
        items << { label: t_recon("loan_end_principal_label"), value: end_balance_before_adjustments, tooltip: t_recon("loan_end_principal_tooltip"), style: :subtotal }
        items << { label: t_recon("adjustments_label"), value: balance.non_cash_adjustments_money, tooltip: t_recon("adjustments_tooltip"), style: :adjustment }
      end

      items << { label: t_recon("loan_final_principal_label"), value: balance.end_balance_money, tooltip: t_recon("loan_final_principal_tooltip"), style: :final }
      items
    end

    def asset_items # Property/Vehicle
      items = [
        { label: t_recon("asset_start_value_label"), value: balance.start_balance_money, tooltip: t_recon("asset_start_value_tooltip"), style: :start },
        { label: t_recon("asset_net_value_change_label"), value: net_total_flow, tooltip: t_recon("asset_net_value_change_tooltip"), style: :flow }
      ]

      if has_adjustments?
        items << { label: t_recon("asset_end_value_label"), value: end_balance_before_adjustments, tooltip: t_recon("asset_end_value_tooltip"), style: :subtotal }
        items << { label: t_recon("adjustments_label"), value: total_adjustments, tooltip: t_recon("asset_adjustments_tooltip"), style: :adjustment }
      end

      items << { label: t_recon("asset_final_value_label"), value: balance.end_balance_money, tooltip: t_recon("asset_final_value_tooltip"), style: :final }
      items
    end

    def crypto_items
      items = [
        { label: t_recon("start_balance_label"), value: balance.start_balance_money, tooltip: t_recon("crypto_start_balance_tooltip"), style: :start }
      ]

      items << { label: t_recon("crypto_buys_label"), value: balance.cash_outflows_money * -1, tooltip: t_recon("crypto_buys_tooltip"), style: :flow } if balance.cash_outflows != 0
      items << { label: t_recon("crypto_sells_label"), value: balance.cash_inflows_money, tooltip: t_recon("crypto_sells_tooltip"), style: :flow } if balance.cash_inflows != 0
      items << { label: t_recon("crypto_market_changes_label"), value: balance.net_market_flows_money, tooltip: t_recon("crypto_market_changes_tooltip"), style: :flow } if balance.net_market_flows != 0

      if has_adjustments?
        items << { label: t_recon("end_balance_label"), value: end_balance_before_adjustments, tooltip: t_recon("crypto_end_balance_tooltip"), style: :subtotal }
        items << { label: t_recon("adjustments_label"), value: total_adjustments, tooltip: t_recon("adjustments_tooltip"), style: :adjustment }
      end

      items << { label: t_recon("final_balance_label"), value: balance.end_balance_money, tooltip: t_recon("crypto_final_balance_tooltip"), style: :final }
      items
    end

    def net_cash_flow
      balance.cash_inflows_money - balance.cash_outflows_money
    end

    def net_non_cash_flow
      balance.non_cash_inflows_money - balance.non_cash_outflows_money
    end

    def net_total_flow
      net_cash_flow + net_non_cash_flow + balance.net_market_flows_money
    end

    def total_adjustments
      balance.cash_adjustments_money + balance.non_cash_adjustments_money
    end

    def has_adjustments?
      balance.cash_adjustments != 0 || balance.non_cash_adjustments != 0
    end

    def end_balance_before_adjustments
      balance.end_balance_money - total_adjustments
    end
end
