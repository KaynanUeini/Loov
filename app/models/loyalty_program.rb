class LoyaltyProgram < ApplicationRecord
  belongs_to :car_wash

  validates :visits_required,    presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 50 }
  validates :reward_description, presence: true, length: { maximum: 120 }
end
