class CarWashClosure < ApplicationRecord
  belongs_to :car_wash

  validates :start_date, :end_date, presence: true
  validate :end_after_start

  private

  def end_after_start
    return unless start_date && end_date
    errors.add(:end_date, "deve ser depois do início") if end_date <= start_date
  end
end
