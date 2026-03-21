class PendingChange < ApplicationRecord
  belongs_to :car_wash
  belongs_to :attendant, class_name: "User"

  STATUSES    = %w[pending approved rejected].freeze
  CHANGE_TYPES = %w[manage_car_wash monthly_costs].freeze

  validates :change_type, inclusion: { in: CHANGE_TYPES }
  validates :status,      inclusion: { in: STATUSES }
  validates :payload,     presence: true

  scope :pending,  -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }

  def payload_data
    JSON.parse(payload) rescue {}
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  def pending?
    status == "pending"
  end
end
