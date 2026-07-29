class CreateSupportTicketMessages < ActiveRecord::Migration[7.1]
  def change
    # if_not_exists: bancos restaurados de dump já têm a tabela sem o registro
    # em schema_migrations. As outras migrations desse lote também são idempotentes.
    create_table :support_ticket_messages, if_not_exists: true do |t|
      t.references :support_ticket, null: false, foreign_key: true
      t.references :user,           null: false, foreign_key: true
      t.text :body,        null: false
      t.boolean :from_admin, null: false, default: false

      t.timestamps
    end
  end
end
