class AttendantActivity < ApplicationRecord
  belongs_to :car_wash
  belongs_to :attendant, class_name: "User"

  validates :action, presence: true

  # Lista estruturada de mudanças para render linha-a-linha no app.
  serialize :items, coder: JSON
end
