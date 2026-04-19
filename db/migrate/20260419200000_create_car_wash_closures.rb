class CreateCarWashClosures < ActiveRecord::Migration[7.1]
  def change
    # A tabela existe no db/schema.rb mas a migration original não foi
    # commitada em algum momento, então em ambientes que rodam
    # `rails db:migrate` (prod) a tabela nunca foi criada. Este arquivo
    # resolve isso de forma idempotente.
    return if table_exists?(:car_wash_closures)

    create_table :car_wash_closures do |t|
      t.references :car_wash, null: false, foreign_key: true
      t.date       :start_date
      t.date       :end_date
      t.string     :reason
      t.timestamps
    end
  end
end
