class SupportTicket < ApplicationRecord
  belongs_to :user
  belongs_to :car_wash, optional: true
  has_many :messages, class_name: "SupportTicketMessage", dependent: :destroy

  CATEGORIES = %w[
    financeiro
    agendamento
    cadastro
    tecnico
    disponivel
    atendente
    cancelamento
    outro
  ].freeze

  STATUSES = %w[open in_progress resolved].freeze

  validates :category, inclusion: { in: CATEGORIES }
  validates :status,   inclusion: { in: STATUSES }

  scope :recent,  -> { order(updated_at: :desc) }
  scope :pending, -> { where(status: %w[open in_progress]) }

  def resolved?
    status == "resolved"
  end

  def status_label
    {
      "open"        => "Aberto",
      "in_progress" => "Em andamento",
      "resolved"    => "Resolvido"
    }[status] || status
  end
end
