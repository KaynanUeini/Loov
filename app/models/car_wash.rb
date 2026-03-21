class CarWash < ApplicationRecord
  belongs_to :user
  has_many :services, dependent: :destroy
  has_many :appointments, dependent: :destroy
  has_many :operating_hours, dependent: :destroy
  has_many :monthly_costs, dependent: :destroy
  has_many :reviews, through: :appointments
  has_many :attendant_invitations, dependent: :destroy
  has_many :pending_changes, dependent: :destroy

  accepts_nested_attributes_for :operating_hours, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :services, allow_destroy: true, reject_if: :all_blank

  validates :name, presence: true
  validates :address, presence: true
  validates :capacity_per_slot, presence: true, numericality: { greater_than: 0 }

  geocoded_by :geocoding_address
  after_validation :geocode, if: :address_changed?

  def geocoding_address
    parts = []
    parts << logradouro if logradouro.present?
    parts << cidade     if cidade.present?
    parts << uf         if uf.present?
    parts << "Brasil"
    parts.join(", ")
  end

  def has_valid_coordinates?
    latitude.present? && longitude.present? && latitude != 0.0 && longitude != 0.0
  end

  def full_address
    [logradouro, bairro, cidade, uf].select(&:present?).join(", ")
  end

  def location_context
    parts = []
    parts << "Bairro: #{bairro}" if bairro.present?
    parts << "Cidade: #{cidade}" if cidade.present?
    parts << "UF: #{uf}" if uf.present?
    parts << "CEP: #{cep}" if cep.present?
    parts.join(" | ")
  end
end
