class MonthlyCost < ApplicationRecord
  belongs_to :car_wash
  has_many :custom_cost_lines, dependent: :destroy

  validates :year,  presence: true
  validates :month, presence: true, inclusion: { in: 1..12 }

  MONTH_NAMES = %w[Janeiro Fevereiro Março Abril Maio Junho Julho Agosto Setembro Outubro Novembro Dezembro]

  def month_name
    MONTH_NAMES[month - 1]
  end

  # Totais incluem os 5 campos padrão + as linhas customizadas do dono.
  # other_fixed e other_variable continuam sendo somados pra não perder
  # dados de meses lançados antes do feature de linhas customizadas; a UI
  # atual não expõe mais esses campos, eles ficam 0 para meses novos.
  def total_fixed
    standard = [rent, salaries, utilities, other_fixed].compact.sum
    standard + custom_cost_lines.fixed_type.sum(:amount).to_f
  end

  def total_variable
    standard = [products, maintenance, other_variable].compact.sum
    standard + custom_cost_lines.variable_type.sum(:amount).to_f
  end

  def total
    total_fixed + total_variable
  end

  def self.for_month(car_wash, year, month)
    find_or_initialize_by(car_wash: car_wash, year: year, month: month)
  end
end
