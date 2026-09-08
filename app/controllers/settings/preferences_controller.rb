class Settings::PreferencesController < ApplicationController
  layout "settings"

  def show
    @user = Current.user
    @family_members = Current.family.users.where.not(id: @user.id).where(active: true)
    @budget_shares = @user.budget_shares_given.index_by(&:viewer_id)
  end

  # Writes per-user preferences stored in the JSONB `users.preferences`
  # column. Mirrors Settings::AppearancesController#update so the toggle card on
  # the Preferences page can submit directly without going through the broader
  # UsersController#update flow (which expects a full user form payload).
  def update
    @user = Current.user
    user_params = params.permit(user: [ :preview_features_enabled, :last_entry_date ]).fetch(:user, {})

    if user_params.key?(:last_entry_date) && !@user.remember_entry_date(user_params[:last_entry_date])
      return head :unprocessable_entity
    end

    if user_params.key?(:preview_features_enabled)
      @user.with_locked_preferences do |updated_prefs|
        updated_prefs["preview_features_enabled"] =
          ActiveModel::Type::Boolean.new.cast(user_params[:preview_features_enabled])
      end
    end
    respond_to do |format|
      format.html { redirect_to settings_preferences_path }
      format.json { head :no_content }
    end
  end
end
