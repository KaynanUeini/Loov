class AttendantInvitation < ApplicationRecord
  belongs_to :car_wash
  belongs_to :inviter, class_name: "User"
  belongs_to :attendant, class_name: "User", optional: true

  STATUSES = %w[pending accepted].freeze

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :generate_token, on: :create

  scope :pending,  -> { where(status: "pending") }
  scope :accepted, -> { where(status: "accepted") }

  def accepted?
    status == "accepted"
  end

  def accept!(user)
    update!(status: "accepted", attendant: user)
    user.update!(role: "attendant")
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end
end
