class CarWash < ApplicationRecord
  belongs_to :user
  has_many :services,              dependent: :destroy
  has_many :appointments,          dependent: :destroy
  has_many :operating_hours,       dependent: :destroy
  has_many :monthly_costs,         dependent: :destroy
  has_many :reviews,               through: :appointments
  has_many :attendant_invitations, dependent: :destroy
  has_many :pending_changes,       dependent: :destroy
  has_many :car_wash_closures,     dependent: :destroy
  has_one :loyalty_program, dependent: :destroy

  accepts_nested_attributes_for :operating_hours, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :services,        allow_destroy: true, reject_if: :all_blank

  validates :name,              presence: true
  validates :address,           presence: true
  validates :capacity_per_slot, presence: true, numericality: { greater_than: 0 }

  geocoded_by :geocoding_address
  after_validation :geocode, if: :should_geocode?

  # Só chama a API do Geocoder quando o endereço mudou E ainda não temos
  # coordenadas válidas. Evita bater no rate limit do Nominatim durante
  # seeds/imports que já trazem lat/lng prontos.
  def should_geocode?
    address_changed? && !has_valid_coordinates?
  end

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

  # Capacidade de atendimento simultâneo no dia da data/hora informada.
  #
  # A equipe varia ao longo da semana (menor no meio, maior no fim de semana),
  # então cada operating_hour pode ter a sua capacidade; sem valor definido,
  # vale o default do lava-rápido. Sempre >= 1 — capacidade zero deixaria a
  # agenda inteira indisponível sem o dono entender o porquê.
  #
  # Recebe Date, Time ou DateTime. Sem argumento com wday (nil), devolve o
  # default. Usa `detect` em vez de `find_by` de propósito: carrega a
  # associação uma vez e as chamadas seguintes do mesmo request batem em
  # memória, o que importa em available_times (dezenas de slots por dia).
  def capacity_for(date_or_time)
    wday = date_or_time.try(:wday)
    hour = wday && operating_hours.detect { |oh| oh.day_of_week == wday }
    return hour.effective_capacity if hour
    [capacity_per_slot.to_i, 1].max
  end

  # Verifica se há um CarWashClosure ativo cobrindo a data informada
  # (default: hoje). Usado pelos endpoints client-facing pra filtrar/marcar
  # como fechado lavas-rápidos com fechamento programado.
  def closed_on?(date = Date.current)
    car_wash_closures.where("start_date <= ? AND end_date >= ?", date, date).exists?
  end

  def full_address
    [logradouro, bairro, cidade, uf].select(&:present?).join(", ")
  end

  def location_context
    parts = []
    parts << "Bairro: #{bairro}" if bairro.present?
    parts << "Cidade: #{cidade}" if cidade.present?
    parts << "UF: #{uf}"        if uf.present?
    parts << "CEP: #{cep}"      if cep.present?
    parts.join(" | ")
  end
end
