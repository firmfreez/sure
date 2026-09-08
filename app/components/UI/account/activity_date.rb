class UI::Account::ActivityDate < ApplicationComponent
  attr_reader :account, :data

  delegate :date, :entries, :balance, :transfers, :split_parents, to: :data

  def initialize(account:, data:)
    @account = account
    @data = data
  end

  def id
    dom_id(account, "entries_#{date}")
  end

  def broadcast_channel
    account
  end

  def end_balance_money
    balance&.end_balance_money || Money.new(0, account.currency)
  end

  def can_add_entry?
    account.permission_for(Current.user).in?([ :owner, :full_control ])
  end

  def new_entry_path
    if account.investment?
      helpers.new_trade_path(account_id: account.id, date: date)
    elsif account.crypto?
      helpers.new_transfer_path(from_account_id: account.id, date: date, return_to: activity_path)
    else
      helpers.new_transaction_path(account_id: account.id, date: date, return_to: activity_path)
    end
  end

  def broadcast_refresh!
    Turbo::StreamsChannel.broadcast_replace_to(
      broadcast_channel,
      target: id,
      renderable: self,
      layout: false
    )
  end

  private
    def activity_path
      helpers.account_path(account, tab: "activity")
    end
end
