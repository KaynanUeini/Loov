class OwnerMessage < ApplicationRecord
  belongs_to :car_wash
  belongs_to :sender,    class_name: "User"
  belongs_to :recipient, class_name: "User", optional: true

  validates :body,   presence: true, length: { maximum: 300 }
  validates :target, inclusion: { in: %w[all user] }

  scope :for_user, ->(user_id, car_wash_id) {
    where(car_wash_id: car_wash_id)
      .where("target = 'all' OR recipient_id = ?", user_id)
      .order(created_at: :desc)
  }
end
