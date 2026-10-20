# Vale de fidelidade: o que o cliente ganhou ao completar o cartão de um
# lava-rápido, pra usar na PRÓXIMA visita (agendamento comum, Last Minute ou
# balcão). As condições ficam congeladas aqui no momento em que ele ganhou —
# o dono mudar o programa depois não mexe no vale de quem já ganhou.
#
# Estado, sem coluna de status pra não sair de sincronia:
#   usado      used_at preenchido (o atendimento em que foi aplicado foi concluído)
#   reservado  preso a um atendimento ainda ativo (confirmado, aguardando aceite
#              ou aguardando o banco)
#   vencido    passou de expires_at sem uso
#   disponível o resto
#
# O "vale volta" quando o atendimento é cancelado, recusado, expira ou o
# cliente falta: o atendimento deixa de estar ativo e o vale volta a ficar
# disponível sozinho — vale pra todo caminho, inclusive os update_all/
# update_columns que não passam por callback.
class LoyaltyReward < ApplicationRecord
  TYPES  = %w[percent fixed free_service gift].freeze
  ATIVOS = %w[confirmed pending_acceptance awaiting_payment].freeze
  # Lembrete antes de vencer.
  AVISO_ANTES = 7.days

  belongs_to :user
  belongs_to :car_wash
  belongs_to :appointment,        optional: true
  belongs_to :earned_appointment, class_name: "Appointment"

  validates :reward_type, inclusion: { in: TYPES }
  validates :description, :expires_at, presence: true

  scope :nao_usados, -> { where(used_at: nil) }
  scope :validos,    -> { nao_usados.where("loyalty_rewards.expires_at > ?", Time.current) }
  scope :livres, -> {
    validos.left_joins(:appointment)
           .where("loyalty_rewards.appointment_id IS NULL OR appointments.status NOT IN (?)", ATIVOS)
  }

  # O vale que entra num atendimento novo deste cliente neste lava-rápido:
  # o que vence primeiro.
  def self.disponivel_para(user, car_wash)
    return nil unless user && car_wash
    livres.where(user_id: user.id, car_wash_id: car_wash.id).order(:expires_at).first
  end

  def usado?     = used_at.present?
  def vencido?   = !usado? && expires_at <= Time.current
  def reservado? = !usado? && appointment.present? && ATIVOS.include?(appointment.status)

  def estado
    return "usado"     if usado?
    return "reservado" if reservado?
    return "vencido"   if vencido?
    "disponivel"
  end

  # Quanto este vale abate de um serviço, sobre o preço que o cliente pagaria
  # (o do agendamento ou o do Last Minute). Nunca passa do preço.
  #   free_service: o serviço do vale sai de graça; outro serviço abate o
  #   preço que o serviço do vale tinha quando ele ganhou (paga a diferença).
  #   gift: brinde entregue no balcão, não mexe no preço.
  def desconto_para(service, base)
    base = base.to_f
    valor = case reward_type
            when "percent"      then base * reward_value.to_f / 100.0
            when "fixed"        then reward_value.to_f
            when "free_service" then service&.id == reward_service_id ? base : reward_value.to_f
            else 0
            end
    valor.clamp(0, base).round(2)
  end

  # Aplica o vale num atendimento ainda não salvo: preço com desconto e o
  # quanto abateu. O vínculo (appointment_id) é gravado depois do save, na
  # mesma transação — ver #reservar!.
  def aplicar_em(appointment, base)
    desconto = desconto_para(appointment.service, base)
    appointment.reward_discount = desconto.positive? ? desconto : nil
    appointment.price_override  = (base.to_f - desconto).round(2) if desconto.positive?
    desconto
  end

  def reservar!(appointment)
    update!(appointment_id: appointment.id)
  end

  # Mesma frase do lado do dono e do cliente.
  def resumo_curto
    case reward_type
    when "percent"      then "#{reward_value.to_f.round}% off"
    when "fixed"        then "R$ #{format('%.2f', reward_value.to_f).sub('.', ',').sub(',00', '')} off"
    when "free_service" then "#{reward_service_title} grátis"
    else description
    end
  end

  def as_cliente
    {
      id:            id,
      type:          reward_type,
      description:   description,
      short:         resumo_curto,
      # value/service_id: o app e o site calculam o desconto antes de
      # confirmar, com a mesma conta de #desconto_para.
      value:         reward_value&.to_f,
      service_id:    reward_service_id,
      expires_at:    expires_at.iso8601,
      state:         estado,
      car_wash_id:   car_wash_id,
      car_wash_name: car_wash&.name
    }
  end
end
