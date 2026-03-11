class CreateAppointments < ActiveRecord::Migration[7.1]
  def change
    create_table :appointments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :car_wash, null: false, foreign_key: true
      t.references :service, null: false, foreign_key: true
      t.datetime :scheduled_at
      t.string :status

      t.timestamps
    end
  end
end
