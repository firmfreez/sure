class AddCascadeDeleteToChatMessagesAndToolCalls < ActiveRecord::Migration[7.2]
  def change
    remove_foreign_key :messages, :chats
    add_foreign_key :messages, :chats, on_delete: :cascade

    remove_foreign_key :tool_calls, :messages
    add_foreign_key :tool_calls, :messages, on_delete: :cascade
  end
end
