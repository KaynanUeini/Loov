class CreateOutreachTables < ActiveRecord::Migration[7.1]
  def change
    create_table :outreach_leads do |t|
      t.string   :name,             null: false
      t.string   :phone
      t.string   :email
      t.text     :address
      t.string   :bairro
      t.string   :cidade,           default: 'Osasco'
      t.decimal  :rating,           precision: 3, scale: 1
      t.text     :reviews_sample
      t.text     :notes
      t.string   :status,           null: false, default: 'novo'
      t.datetime :last_contact_at
      t.timestamps
    end
    add_index :outreach_leads, :status
    add_index :outreach_leads, :phone, unique: true, where: "phone IS NOT NULL"

    create_table :outreach_messages do |t|
      t.references :lead, null: false, foreign_key: { to_table: :outreach_leads }
      t.text       :body, null: false
      t.string     :channel, null: false, default: 'whatsapp'
      t.datetime   :sent_at
      t.timestamps
    end

    create_table :outreach_meetings do |t|
      t.references :lead, null: false, foreign_key: { to_table: :outreach_leads }
      t.datetime   :scheduled_at, null: false
      t.string     :kind, default: 'video'
      t.string     :status, default: 'agendado'
      t.text       :notes
      t.timestamps
    end
  end
end
