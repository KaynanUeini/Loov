class AddStatusToAiInsights < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_insights, :status,        :string, default: "ready", null: false
    add_column :ai_insights, :error_message, :text
  end
end
