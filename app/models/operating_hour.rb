class OperatingHour < ApplicationRecord
  belongs_to :car_wash

  validates :day_of_week, presence: true, inclusion: { in: 0..6 }, uniqueness: { scope: :car_wash_id }
  validates :opens_at, presence: true
  validates :closes_at, presence: true
  validate :closes_after_opens

  # Método para converter o day_of_week (0-6) em um nome legível
  def day_of_week_name
    return "Desconhecido" if day_of_week.nil?

    days = %w[Domingo Segunda-feira Terça-feira Quarta-feira Quinta-feira Sexta-feira Sábado]
    days[day_of_week] || "Desconhecido"
  end

  private

  def closes_after_opens
    if opens_at && closes_at && closes_at <= opens_at
      Rails.logger.error "Validation failed: closes_at (#{closes_at}) must be after opens_at (#{opens_at})"
      errors.add(:closes_at, "must be after the opening time")
    end
  end
end
