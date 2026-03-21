class CreateAttendantInvitations < ActiveRecord::Migration[7.1]
  def change
    create_table :attendant_invitations do |t|
      t.integer :car_wash_id
      t.integer :inviter_id
      t.integer :attendant_id
      t.string :email
      t.string :token
      t.string :status

      t.timestamps
    end
  end
end
