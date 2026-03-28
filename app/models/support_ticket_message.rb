class SupportTicketMessage < ApplicationRecord
  belongs_to :support_ticket
  belongs_to :user

  scope :chronological, -> { order(created_at: :asc) }

  def from_admin?
    from_admin == true
  end
end
