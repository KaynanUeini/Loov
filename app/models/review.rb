class Review < ApplicationRecord
  belongs_to :appointment
  belongs_to :car_wash
  belongs_to :user

  TAGS = [
    "Limpeza impecável",
    "Atendimento rápido",
    "Ótimo preço",
    "Equipe simpática",
    "Fácil de agendar"
  ].freeze

  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :appointment_id, uniqueness: { message: "já foi avaliado" }

  def tags_list
    return [] if tags.blank?
    tags.split(",")
  end
end
