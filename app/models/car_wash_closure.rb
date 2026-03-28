class CarWashClosure < ApplicationRecord
  belongs_to :car_wash

  validates :starts_at, :ends_at, presence: true
  validate :ends_after_starts

  private

  def ends_after_starts
    return unless starts_at && ends_at
    errors.add(:ends_at, "deve ser depois do início") if ends_at <= starts_at
  end
end
