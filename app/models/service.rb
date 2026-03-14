class Service < ApplicationRecord
  CATEGORIES = [
    "Lavagem",
    "Polimento",
    "Higienização",
    "Cristalização",
    "Vitrificação",
    "Enceramento",
    "Hidratação de Couro",
    "Limpeza de Motor",
    "Revitalização de Plásticos",
    "Polimento de Faróis",
    "Impermeabilização",
    "Oxi-sanitização",
    "Outros"
  ].freeze

  GROUPS = {
    "Lavagem"   => ["Lavagem"],
    "Estética"  => ["Polimento", "Cristalização", "Vitrificação", "Enceramento"],
    "Higiene"   => ["Higienização", "Hidratação de Couro", "Impermeabilização", "Oxi-sanitização"],
    "Especiais" => ["Limpeza de Motor", "Revitalização de Plásticos", "Polimento de Faróis"],
    "Outros"    => ["Outros"]
  }.freeze

  belongs_to :car_wash
  has_many :appointments, dependent: :destroy

  validates :title, :price, :duration, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :duration, numericality: { greater_than: 0 }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
end
