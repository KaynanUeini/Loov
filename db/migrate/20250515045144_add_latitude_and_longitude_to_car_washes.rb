class AddLatitudeAndLongitudeToCarWashes < ActiveRecord::Migration[7.1]
  def change
    add_column :car_washes, :latitude, :decimal
    add_column :car_washes, :longitude, :decimal
  end
end
