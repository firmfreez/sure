class HideAiSidebarByDefault < ActiveRecord::Migration[7.1]
  def up
    change_column_default :users, :show_ai_sidebar, from: true, to: false
    User.update_all(show_ai_sidebar: false)
  end

  def down
    change_column_default :users, :show_ai_sidebar, from: false, to: true
  end
end
