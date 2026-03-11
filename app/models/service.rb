class Service < ApplicationRecord
  CATEGORIES = %w[Lavagem Polimento Higienização Cristalização Outros].freeze

  belongs_to :car_wash
  has_many :appointments, dependent: :destroy
  validates :title, :price, :duration, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :duration, numericality: { greater_than: 0 }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
end
