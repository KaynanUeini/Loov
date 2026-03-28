class AddAgentDraftToSupportTickets < ActiveRecord::Migration[7.1]
  def change
    add_column :support_tickets, :agent_draft,      :text
    add_column :support_tickets, :agent_drafted_at, :datetime
    add_column :support_tickets, :agent_sent,       :boolean, default: false, null: false
  end
end
