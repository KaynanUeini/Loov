class Appointment < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :car_wash
  belongs_to :service
  has_one :review, dependent: :destroy

  validates :scheduled_at, presence: true
  validates :walk_in_name, presence: true, if: :walk_in?

  def effective_price
    price_override.present? ? price_override.to_f : service.price.to_f
  end

  def display_client
    if walk_in?
      walk_in_name.presence || "Avulso"
    else
      user&.email&.split("@")&.first&.capitalize || "Cliente"
    end
  end

  def reviewable?
    status == "confirmed" && scheduled_at < Time.current && review.nil? && !walk_in?
  end

  validate :within_operating_hours, unless: :walk_in?

  private

  def within_operating_hours
    return unless scheduled_at && car_wash
    day_of_week = scheduled_at.wday
    operating_hour = car_wash.operating_hours.find_by(day_of_week: day_of_week)
    unless operating_hour
      errors.add(:scheduled_at, "fora do intervalo de funcionamento: nenhum horário definido para este dia")
      return
    end
    scheduled_time    = scheduled_at.to_time
    opens_at          = Time.parse(operating_hour.opens_at.to_s).seconds_since_midnight
    closes_at         = Time.parse(operating_hour.closes_at.to_s).seconds_since_midnight
    scheduled_seconds = scheduled_time.seconds_since_midnight
    unless scheduled_seconds.between?(opens_at, closes_at)
      errors.add(:scheduled_at, "fora do intervalo de funcionamento")
    end
  end
end
