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

  # Push pra quem abriu o chamado quando a equipe responde pelo painel admin.
  # Sem isso, a resposta ficava parada até a pessoa abrir o Suporte por conta
  # própria. Falha de push nunca derruba a resposta.
  def notify_reply!(body)
    ExpoPushNotifier.new.notify_user(
      user,
      title: "Suporte Loov respondeu",
      body:  body.to_s.squish.truncate(120),
      data:  { type: "support_reply", ticket_id: id, role: user.role }
    )
  rescue => e
    Rails.logger.error("[SupportTicket] push da resposta ##{id} falhou: #{e.message}")
  end

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
