class CustomCostLine < ApplicationRecord
  belongs_to :monthly_cost

  COST_TYPES = %w[fixed variable].freeze

  validates :name,      presence: true, length: { maximum: 80 }
  validates :cost_type, inclusion: { in: COST_TYPES }
  validates :amount,    numericality: { greater_than_or_equal_to: 0 }

  scope :fixed_type,    -> { where(cost_type: "fixed") }
  scope :variable_type, -> { where(cost_type: "variable") }
  scope :ordered,       -> { order(:position, :id) }
end
