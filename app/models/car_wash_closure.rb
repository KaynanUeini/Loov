class CarWashClosure < ApplicationRecord
  belongs_to :car_wash

  validates :start_date, :end_date, presence: true
  validate :end_after_start
  validate :not_in_the_past, on: :create

  scope :upcoming_or_active, -> {
    where("end_date >= ?", Date.current).order(:start_date)
  }

  def covers?(date)
    date = date.to_date
    date >= start_date && date <= end_date
  end

  def single_day?
    start_date == end_date
  end

  def display_period
    s = start_date.strftime("%d/%m/%Y")
    e = end_date.strftime("%d/%m/%Y")
    single_day? ? s : "#{s} até #{e}"
  end

  private

  def end_after_start
    return unless start_date && end_date
    errors.add(:end_date, "deve ser igual ou posterior à data de início") if end_date < start_date
  end

  def not_in_the_past
    return unless end_date
    errors.add(:end_date, "não pode ser no passado") if end_date < Date.current
  end
end
