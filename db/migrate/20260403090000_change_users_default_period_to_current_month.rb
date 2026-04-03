class ChangeUsersDefaultPeriodToCurrentMonth < ActiveRecord::Migration[8.0]
  def up
    change_column_default :users, :default_period, from: "last_30_days", to: "current_month"

    execute <<~SQL
      UPDATE users
      SET default_period = 'current_month'
      WHERE default_period = 'last_30_days'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE users
      SET default_period = 'last_30_days'
      WHERE default_period = 'current_month'
    SQL

    change_column_default :users, :default_period, from: "current_month", to: "last_30_days"
  end
end
