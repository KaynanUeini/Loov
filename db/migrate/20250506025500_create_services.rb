class CreateServices < ActiveRecord::Migration[7.1]
  def change
    create_table :services do |t|
      t.string :title
      t.text :description
      t.decimal :price
      t.integer :duration
      t.references :car_wash, null: false, foreign_key: true

      t.timestamps
    end
  end
end
