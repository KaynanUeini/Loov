class AttendantActivity < ApplicationRecord
  belongs_to :car_wash
  belongs_to :attendant, class_name: "User"

  validates :action, presence: true
end
