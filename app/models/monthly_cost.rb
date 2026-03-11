class MonthlyCost < ApplicationRecord
  belongs_to :car_wash

  validates :year,  presence: true
  validates :month, presence: true, inclusion: { in: 1..12 }

  MONTH_NAMES = %w[Janeiro Fevereiro Março Abril Maio Junho Julho Agosto Setembro Outubro Novembro Dezembro]

  def month_name
    MONTH_NAMES[month - 1]
  end

  def total_fixed
    [rent, salaries, utilities, other_fixed].compact.sum
  end

  def total_variable
    [products, maintenance, other_variable].compact.sum
  end

  def total
    total_fixed + total_variable
  end

  def self.for_month(car_wash, year, month)
    find_or_initialize_by(car_wash: car_wash, year: year, month: month)
  end
end
