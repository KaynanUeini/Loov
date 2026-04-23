class CreateAiInsightRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_insight_runs do |t|
      t.references :ai_insight, foreign_key: true, null: true
      t.references :car_wash,   foreign_key: true, null: false

      t.string  :status,          null: false
      t.string  :model
      t.string  :cycle_type
      t.boolean :is_crisis_mode,  default: false, null: false

      t.text    :owner_input
      t.text    :prompt
      t.text    :raw_response
      t.jsonb   :parsed_content

      t.boolean :parse_ok,        default: false, null: false
      t.text    :parse_error

      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :latency_ms

      t.text    :error_message

      t.timestamps
    end

    add_index :ai_insight_runs, :created_at
    add_index :ai_insight_runs, [:car_wash_id, :created_at]
    add_index :ai_insight_runs, :status
  end
end
