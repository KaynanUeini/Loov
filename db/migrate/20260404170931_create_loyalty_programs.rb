class CreateLoyaltyPrograms < ActiveRecord::Migration[7.1]
  def change
    create_table :loyalty_programs do |t|
      t.references :car_wash, null: false, foreign_key: true
      t.integer :visits_required, null: false, default: 5
      t.string  :reward_description, null: false, default: "Serviço gratuito"
      t.boolean :active, null: false, default: true
      t.timestamps
    end
  end
end
