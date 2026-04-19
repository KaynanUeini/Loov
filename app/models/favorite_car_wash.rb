class FavoriteCarWash < ApplicationRecord
  belongs_to :user
  belongs_to :car_wash

  validates :user_id, uniqueness: { scope: :car_wash_id }
end
