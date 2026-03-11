class CreateAiInsights < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_insights do |t|
      t.references :car_wash, null: false, foreign_key: true
      t.string :insight_type
      t.text :content
      t.datetime :generated_at

      t.timestamps
    end
  end
end
