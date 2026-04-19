class CreateFavoriteCarWashes < ActiveRecord::Migration[7.1]
  def change
    create_table :favorite_car_washes do |t|
      t.references :user,     null: false, foreign_key: true
      t.references :car_wash, null: false, foreign_key: true
      t.timestamps
    end
    add_index :favorite_car_washes, [:user_id, :car_wash_id], unique: true
  end
end
