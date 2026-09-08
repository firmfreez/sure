class Transactions::BulkDeletionsController < ApplicationController
  def create
    # Exclude split children from bulk delete - they must be deleted via unsplit on parent
    # Only allow deletion from accounts where user has owner or full_control permission
    writable_account_ids = writable_accounts.pluck(:id)
    entries_scope = Current.family.entries
                      .where(account_id: writable_account_ids)
                      .where(parent_entry_id: nil)
    destroyed = []
    accounts_to_sync = []
    entries_scope.where(id: bulk_delete_params[:entry_ids]).each do |entry|
      unless Entry.exists?(entry.id)
        destroyed << entry
        next
      end

      transfer = entry.entryable.is_a?(Transaction) ? entry.transaction.transfer : nil
      if transfer
        next unless [ transfer.from_account.id, transfer.to_account.id ].all? { |id| writable_account_ids.include?(id) }

        transfer.destroy_with_entries!
      else
        entry.destroy!
        accounts_to_sync << entry.account
      end
      destroyed << entry
    end
    Account::BalanceRefresh.call(accounts_to_sync)
    accounts_to_sync.uniq.each(&:sync_later)
    redirect_back_or_to transactions_url, notice: "#{destroyed.count} transaction#{destroyed.count == 1 ? "" : "s"} deleted"
  end

  private
    def bulk_delete_params
      params.require(:bulk_delete).permit(entry_ids: [])
    end

    def writable_accounts
      Current.family.accounts.writable_by(Current.user)
    end
end
