class CreateReviews < ActiveRecord::Migration[7.1]
  def change
    create_table :reviews do |t|
      t.references :appointment, null: false, foreign_key: true
      t.references :car_wash, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :rating
      t.string :tags
      t.text :comment

      t.timestamps
    end
  end
end
