class PendingChange < ApplicationRecord
  belongs_to :car_wash
  belongs_to :attendant, class_name: "User"

  STATUSES    = %w[pending approved rejected].freeze
  CHANGE_TYPES = %w[manage_car_wash monthly_costs].freeze

  validates :change_type, inclusion: { in: CHANGE_TYPES }
  validates :status,      inclusion: { in: STATUSES }
  validates :payload,     presence: true

  scope :pending,  -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }

  after_create_commit :notify_owner_of_pending!

  def payload_data
    JSON.parse(payload) rescue {}
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  def pending?
    status == "pending"
  end

  private

  # Push pro dono do lava-rápido quando o atendente cria uma alteração
  # pendente de aprovação.
  def notify_owner_of_pending!
    return unless pending?
    owner = car_wash&.user
    return unless owner
    return if owner == attendant   # safety: nunca notifica o próprio autor

    title = case change_type
            when "manage_car_wash" then "Alteração no Gerenciar lava-rápido"
            when "monthly_costs"   then "Alteração nos custos mensais"
            else "Alteração aguardando aprovação"
            end
    body = "#{attendant&.display_name || 'Um atendente'} pediu aprovação · #{description.to_s.truncate(120)}"

    ExpoPushNotifier.new.notify_user(
      owner,
      title: title,
      body:  body,
      data:  { type: "pending_change", pending_change_id: id, change_type: change_type }
    )
  rescue => e
    Rails.logger.warn("[PendingChange] push falhou: #{e.class}: #{e.message}")
  end
end
