class Payment < ApplicationRecord
  belongs_to :appointment

  validates :amount, presence: true
  validates :stripe_charge_id, presence: true
end
