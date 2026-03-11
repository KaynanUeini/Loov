class AddOwnerInputToAiInsights < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_insights, :owner_input, :text
    add_column :ai_insights, :owner_input_at, :datetime
  end
end
