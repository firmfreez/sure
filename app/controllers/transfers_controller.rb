class TransfersController < ApplicationController
  include StreamExtensions

  before_action :set_transfer, only: %i[show destroy update]

  def new
    @transfer = Transfer.new
    @return_to = safe_return_to_path || safe_referer_path
    @from_account_id = params[:from_account_id]
  end

  def show
    @categories = Current.family.categories.expenses
  end

  def create
    @transfer = Transfer::Creator.new(
      family: Current.family,
      source_account_id: transfer_params[:from_account_id],
      destination_account_id: transfer_params[:to_account_id],
      date: transfer_params[:date],
      amount: transfer_params[:amount].to_d
    ).create

    redirect_path = safe_return_to_path || safe_referer_path || transactions_path

    if @transfer.persisted?
      materialize_account_balance_now(@transfer.from_account)
      materialize_account_balance_now(@transfer.to_account)

      success_message = t(".success")
      respond_to do |format|
        format.html { redirect_to redirect_path, notice: success_message }
        format.turbo_stream { stream_redirect_to redirect_path, notice: success_message }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    Transfer.transaction do
      update_transfer_status
      update_transfer_details unless transfer_update_params[:status] == "rejected"
    end

    respond_to do |format|
      format.html { redirect_back_or_to transactions_url, notice: t(".success") }
      format.turbo_stream
    end
  end

  def destroy
    from_account = @transfer.from_account
    to_account = @transfer.to_account

    @transfer.destroy_with_entries!
    materialize_account_balance_now(from_account)
    materialize_account_balance_now(to_account)

    redirect_back_or_to transactions_url, notice: t(".success")
  end

  private
    def set_transfer
      # Finds the transfer and ensures the family owns it
      @transfer = Transfer
                    .where(id: params[:id])
                    .where(inflow_transaction_id: Current.family.transactions.select(:id))
                    .first!
    end

    def transfer_params
      params.require(:transfer).permit(:from_account_id, :to_account_id, :amount, :date, :name, :excluded)
    end

    def transfer_update_params
      params.require(:transfer).permit(:notes, :status, :category_id)
    end

    def safe_return_to_path
      sanitize_path(params[:return_to])
    end

    def safe_referer_path
      sanitize_path(request.referer)
    end

    def sanitize_path(value)
      return nil if value.blank?

      raw_value = value.to_s

      begin
        uri = URI.parse(raw_value)
      rescue URI::InvalidURIError
        return nil
      end

      if uri.host.present?
        return nil unless uri.host == request.host

        path = uri.path.presence || "/"
        query = uri.query.present? ? "?#{uri.query}" : ""
        "#{path}#{query}"
      else
        return nil unless raw_value.start_with?("/")

        raw_value
      end
    end

    def update_transfer_status
      if transfer_update_params[:status] == "rejected"
        @transfer.reject!
      elsif transfer_update_params[:status] == "confirmed"
        @transfer.confirm!
      end
    end

    def update_transfer_details
      @transfer.outflow_transaction.update!(category_id: transfer_update_params[:category_id])
      @transfer.update!(notes: transfer_update_params[:notes])
    end

    # Keep account balances fresh immediately for the response path.
    # We still enqueue async sync for full recalculation workflows.
    def materialize_account_balance_now(account)
      return unless account

      strategy = account.linked? ? :reverse : :forward
      Balance::Materializer.new(account, strategy: strategy).materialize_balances
      account.reload
    rescue StandardError => e
      Rails.logger.warn("TransfersController immediate balance materialization failed for account #{account.id}: #{e.class} - #{e.message}")
    end
end
