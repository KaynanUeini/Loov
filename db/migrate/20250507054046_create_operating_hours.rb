class CreateOperatingHours < ActiveRecord::Migration[7.1]
  def change
    create_table :operating_hours do |t|
      t.references :car_wash, null: false, foreign_key: true
      t.integer :day_of_week
      t.time :opens_at
      t.time :closes_at

      t.timestamps
    end
  end
end
