class CreateAttendantActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :attendant_activities do |t|
      t.references :car_wash,  null: false, foreign_key: true
      t.references :attendant, null: false, foreign_key: { to_table: :users }
      t.string :action,  null: false   # ex: "manage_car_wash"
      t.string :title
      t.text   :body

      t.timestamps
    end

    add_index :attendant_activities, [:car_wash_id, :created_at]
  end
end
