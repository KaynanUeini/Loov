class AddResolvedAtToSupportTickets < ActiveRecord::Migration[7.1]
  def change
    add_column :support_tickets, :resolved_at, :datetime unless column_exists?(:support_tickets, :resolved_at)
    add_column :support_tickets, :replied_at,  :datetime unless column_exists?(:support_tickets, :replied_at)
    add_column :support_tickets, :admin_reply, :text     unless column_exists?(:support_tickets, :admin_reply)
  end
end
