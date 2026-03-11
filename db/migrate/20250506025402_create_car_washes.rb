class CreateCarWashes < ActiveRecord::Migration[7.1]
  def change
    create_table :car_washes do |t|
      t.string :name
      t.string :address
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
