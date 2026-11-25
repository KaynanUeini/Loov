# Cliente de Last Minute pagou e diz que não foi atendido (botão Ajuda do
# card, da hora do início até 24h depois). Regra escrita na Central de Ajuda
# (/ajuda/nao-fui-atendido e /ajuda/suspensao-last-minute):
#
#   · o dono tem 24h pra responder;
#   · confirmou ou não respondeu: o cliente recebe de volta o que pagou no app,
#     e o caso conta pra loja;
#   · discordou: a equipe da Loov decide (procedente devolve e conta;
#     improcedente não devolve e não conta);
#   · 3 casos contados em 60 dias suspendem o Last Minute da loja por 30 dias.
#
# Sem fila de tarefas: o prazo vencido é resolvido na hora em que alguém olha
# (vencer!), pelo card do cliente, pelo painel do dono, pelo admin e pelo
# gatilho diário.
class NaoAtendido < ApplicationRecord
  belongs_to :appointment
  belongs_to :user
  belongs_to :car_wash
  belongs_to :support_ticket, optional: true

  STATUSES        = %w[aguardando confirmado sem_resposta contestado procedente improcedente].freeze
  CONTAM          = %w[confirmado sem_resposta procedente].freeze
  JANELA_AJUDA    = 24.hours  # do horário do início até quando o cliente pode pedir
  PRAZO_DONO      = 24.hours
  JANELA_CASOS    = 60.days
  CASOS_SUSPENDEM = 3
  SUSPENSAO       = 30.days

  validates :status, inclusion: { in: STATUSES }
  validates :appointment_id, uniqueness: true

  scope :aguardando, -> { where(status: "aguardando") }
  scope :contados,   -> { where.not(contado_em: nil) }

  def self.abrir!(appointment, relato)
    caso = create!(
      appointment: appointment, user: appointment.user, car_wash: appointment.car_wash,
      relato: relato.to_s.strip.first(1000), valor: appointment.prepayment_amount,
      prazo_em: Time.current + PRAZO_DONO
    )
    caso.avisar_dono
    caso
  end

  # Prazo do dono vencido sem resposta: vale como confirmado.
  def self.vencer!(scope = all)
    scope.aguardando.where("prazo_em <= ?", Time.current).find_each do |c|
      c.with_lock { c.resolver!("sem_resposta") if c.status == "aguardando" }
    rescue => e
      Rails.logger.error("[NaoAtendido##{c.id}] vencer falhou: #{e.class}: #{e.message}")
    end
  end

  # Datas (contado_em) dos casos que contam, do mais antigo pro mais novo,
  # dentro do alcance de uma suspensão ainda valendo (60 + 30 dias).
  def self.datas_contadas(car_wash_id, agora = Time.current)
    contados.where(car_wash_id: car_wash_id)
            .where("contado_em > ?", agora - JANELA_CASOS - SUSPENSAO)
            .order(:contado_em).pluck(:contado_em)
  end

  # Até quando o Last Minute da loja está suspenso (nil se não está). O 3º
  # caso dentro de 60 dias suspende por 30 dias a partir dele.
  def self.suspenso_ate(car_wash_id, agora = Time.current)
    datas = datas_contadas(car_wash_id, agora)
    fins = datas.each_with_index.filter_map do |d, i|
      janela = datas[0..i].count { |x| x > d - JANELA_CASOS }
      d + SUSPENSAO if janela >= CASOS_SUSPENDEM
    end
    fim = fins.max
    fim if fim && fim > agora
  end

  # Situação da loja pro painel do dono.
  def self.situacao(car_wash, agora = Time.current)
    vencer!(where(car_wash_id: car_wash.id))
    ate = suspenso_ate(car_wash.id, agora)
    recentes = contados.where(car_wash_id: car_wash.id).where("contado_em > ?", agora - JANELA_CASOS).order(:contado_em).pluck(:contado_em)
    {
      suspenso_ate: ate&.iso8601,
      casos: (ate ? datas_contadas(car_wash.id, agora).select { |d| d > ate - SUSPENSAO - JANELA_CASOS && d <= ate - SUSPENSAO } : recentes).map(&:iso8601),
      recentes: recentes.size,
      limite: CASOS_SUSPENDEM
    }
  end

  def contado?; contado_em.present?; end

  def confirmar!(por:, resposta: nil)
    with_lock do
      return false unless status == "aguardando"
      self.resposta_dono = resposta.presence
      self.respondido_por_id = por.id
      self.respondido_em = Time.current
      resolver!("confirmado")
    end
    true
  end

  def contestar!(por:, resposta:)
    with_lock do
      return false unless status == "aguardando"
      update!(status: "contestado", resposta_dono: resposta.to_s.strip.first(1000),
              respondido_por_id: por.id, respondido_em: Time.current)
    end
    abrir_chamado_da_equipe
    true
  end

  def decidir!(procedente:, por:)
    with_lock do
      return false unless status == "contestado"
      self.decidido_por_id = por.id
      self.decidido_em = Time.current
      if procedente
        resolver!("procedente")
      else
        update!(status: "improcedente")
      end
    end
    avisar_cliente_da_decisao(procedente)
    true
  end

  # Devolve o pago no app e passa a contar pra suspensão.
  def resolver!(novo_status)
    resultado = appointment.estornar_prepagamento!
    update!(status: novo_status, contado_em: Time.current, estorno: resultado == :ok ? "ok" : "failed")
    avisar_cliente_do_estorno unless novo_status == "procedente"
  end

  def codigo
    "LV-#{appointment_id.to_s.rjust(4, '0')}"
  end

  # Como o cliente vê o pedido no card.
  def resumo_cliente
    {
      status: status,
      prazo_em: prazo_em&.iso8601,
      valor: valor.to_f,
      devolvido: CONTAM.include?(status),
      estorno: estorno
    }
  end

  # Como o dono vê o caso no painel.
  def resumo_dono
    a = appointment
    {
      id: id,
      codigo: codigo,
      cliente: a.display_client,
      servico: a.service&.title,
      horario: a.scheduled_at&.iso8601,
      relato: relato,
      valor: valor.to_f,
      prazo_em: prazo_em&.iso8601,
      status: status
    }
  end

  def avisar_dono
    dono = car_wash.user
    return if dono.blank? || dono == user
    horario = appointment.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%H:%M")
    ExpoPushNotifier.new.notify_user(
      dono,
      title: "Cliente diz que não foi atendido",
      body:  "#{appointment.display_client}, Last Minute das #{horario}. Responda em até 24h; sem resposta, o valor volta pro cliente.",
      data:  { type: "nao_atendido", nao_atendido_id: id, car_wash_id: car_wash_id }
    )
  rescue => e
    Rails.logger.error("[NaoAtendido##{id}] push pro dono falhou: #{e.class}: #{e.message}")
  end

  private

  def avisar_cliente_do_estorno
    ExpoPushNotifier.new.notify_user(
      user,
      title: "Valor devolvido",
      body:  "Os #{dinheiro(valor)} da reserva #{codigo} voltam pro seu cartão. O prazo pra aparecer depende do banco.",
      data:  { type: "nao_atendido_estorno", appointment_id: appointment_id }
    )
  rescue => e
    Rails.logger.error("[NaoAtendido##{id}] push pro cliente falhou: #{e.class}: #{e.message}")
  end

  def avisar_cliente_da_decisao(procedente)
    texto = if procedente
      "A equipe analisou a reserva #{codigo} e devolveu os #{dinheiro(valor)} pro seu cartão. O prazo pra aparecer depende do banco."
    else
      "A equipe analisou a reserva #{codigo} com o lava-rápido e não encontrou motivo pra devolver o valor. Se quiser, responda por aqui."
    end
    support_ticket&.messages&.create!(user: User.find_by(role: "admin") || user, from_admin: true, body: texto)
    ExpoPushNotifier.new.notify_user(user, title: procedente ? "Valor devolvido" : "Pedido analisado", body: texto,
                                     data: { type: "nao_atendido_decisao", appointment_id: appointment_id })
  rescue => e
    Rails.logger.error("[NaoAtendido##{id}] aviso da decisão falhou: #{e.class}: #{e.message}")
  end

  # Discordou: a conversa nasce no suporte do cliente, onde a equipe responde.
  def abrir_chamado_da_equipe
    ticket = user.support_tickets.create!(
      category: "disponivel", status: "open", car_wash: car_wash,
      description: "Não fui atendido · #{codigo} · o lava-rápido discordou"
    )
    ticket.messages.create!(user: user, from_admin: false, body: relato.presence || "Não fui atendido.")
    ticket.messages.create!(
      user: User.find_by(role: "admin") || user, from_admin: true,
      body: "#{car_wash.name} discordou: \"#{resposta_dono}\". A equipe da Loov vai analisar e te responde por aqui."
    )
    update_columns(support_ticket_id: ticket.id)
  rescue => e
    Rails.logger.error("[NaoAtendido##{id}] não abriu chamado: #{e.class}: #{e.message}")
  end

  def dinheiro(v)
    "R$ #{format('%.2f', v.to_f).tr('.', ',')}"
  end
end
