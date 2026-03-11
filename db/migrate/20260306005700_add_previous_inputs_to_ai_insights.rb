class AddPreviousInputsToAiInsights < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_insights, :previous_inputs, :text
  end
end
