class NotificationRead < ApplicationRecord
  belongs_to :user

  validates :key, presence: true, uniqueness: { scope: :user_id }
  validates :read_at, presence: true
end
