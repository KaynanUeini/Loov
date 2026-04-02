class CeoAssistantService
  def initialize
    @now        = Time.current
    @month_start = @now.beginning_of_month
    @month_end   = @now.end_of_month
    @prev_start  = 1.month.ago.beginning_of_month
    @prev_end    = 1.month.ago.end_of_month
    @week_start  = @now.beginning_of_week
  end

  def generate_briefing(focus: nil)
    data   = aggregate_platform_data
    prompt = build_prompt(data, focus)
    call_claude(prompt)
  rescue => e
    Rails.logger.error("[CeoAssistant] Erro: #{e.message}")
    { error: e.message }
  end

  private

  # ── AGREGAÇÃO DE DADOS ───────────────────────────────────────────────────

  def aggregate_platform_data
    {
      snapshot_at: @now.strftime("%d/%m/%Y %H:%M"),
      platform:    platform_metrics,
      growth:      growth_metrics,
      monetization: monetization_metrics,
      retention:   retention_metrics,
      supply:      supply_metrics,
      support:     support_metrics,
      health:      health_metrics
    }
  end

  def platform_metrics
    total_users    = User.count
    total_owners   = User.where(role: "owner").count
    total_clients  = User.where(role: "client").count
    active_cws     = CarWash.where(active: true).count
    total_cws      = CarWash.count
    total_appts    = Appointment.where.not(status: "cancelled").count
    attended_appts = Appointment.where(status: "attended").count
    conversion_pct = total_appts > 0 ? (attended_appts.to_f / total_appts * 100).round(1) : 0

    {
      total_users:       total_users,
      total_owners:      total_owners,
      total_clients:     total_clients,
      total_car_washes:  total_cws,
      active_car_washes: active_cws,
      total_appointments: total_appts,
      attended_appointments: attended_appts,
      show_rate_pct:     conversion_pct
    }
  end

  def growth_metrics
    new_users_month   = User.where(created_at: @month_start..@month_end).count
    new_users_prev    = User.where(created_at: @prev_start..@prev_end).count
    new_owners_month  = User.where(role: "owner", created_at: @month_start..@month_end).count
    new_clients_month = User.where(role: "client", created_at: @month_start..@month_end).count
    new_cws_month     = CarWash.where(created_at: @month_start..@month_end).count
    appts_this_month  = Appointment.where(scheduled_at: @month_start..@month_end).where.not(status: "cancelled").count
    appts_prev_month  = Appointment.where(scheduled_at: @prev_start..@prev_end).where.not(status: "cancelled").count
    appts_this_week   = Appointment.where(scheduled_at: @week_start..@now).where.not(status: "cancelled").count

    user_growth_pct = new_users_prev > 0 ? ((new_users_month - new_users_prev).to_f / new_users_prev * 100).round(1) : nil
    appt_growth_pct = appts_prev_month > 0 ? ((appts_this_month - appts_prev_month).to_f / appts_prev_month * 100).round(1) : nil

    {
      new_users_this_month:   new_users_month,
      new_users_prev_month:   new_users_prev,
      user_growth_pct:        user_growth_pct,
      new_owners_this_month:  new_owners_month,
      new_clients_this_month: new_clients_month,
      new_car_washes_month:   new_cws_month,
      appointments_this_month: appts_this_month,
      appointments_prev_month: appts_prev_month,
      appointment_growth_pct:  appt_growth_pct,
      appointments_this_week:  appts_this_week
    }
  end

  def monetization_metrics
    # Receita de Disponíveis (comissão Loov)
    commission_month = Appointment
      .where(appointment_type: "disponivel", status: "attended")
      .where(scheduled_at: @month_start..@month_end)
      .sum(:commission_amount).to_f.round(2)

    commission_prev = Appointment
      .where(appointment_type: "disponivel", status: "attended")
      .where(scheduled_at: @prev_start..@prev_end)
      .sum(:commission_amount).to_f.round(2)

    commission_total = Appointment
      .where(appointment_type: "disponivel", status: "attended")
      .sum(:commission_amount).to_f.round(2)

    # Volume total transacionado na plataforma
    volume_month = Appointment
      .where(status: "attended")
      .where(scheduled_at: @month_start..@month_end)
      .joins(:service).sum("services.price").to_f.round(2)

    volume_total = Appointment
      .where(status: "attended")
      .joins(:service).sum("services.price").to_f.round(2)

    # Disponíveis
    disp_count_month  = Appointment.where(appointment_type: "disponivel").where(scheduled_at: @month_start..@month_end).count
    disp_attended_month = Appointment.where(appointment_type: "disponivel", status: "attended").where(scheduled_at: @month_start..@month_end).count
    total_attended_month = Appointment.where(status: "attended").where(scheduled_at: @month_start..@month_end).count
    disp_pct = total_attended_month > 0 ? (disp_attended_month.to_f / total_attended_month * 100).round(1) : 0

    # Owners sem nenhum Disponível
    owners_with_disp = Appointment.where(appointment_type: "disponivel").pluck(:car_wash_id).uniq.count
    owners_without_disp = CarWash.where(active: true).count - owners_with_disp

    # Ticket médio
    avg_ticket = Appointment.where(status: "attended").joins(:service).average("services.price").to_f.round(2) rescue 0

    {
      commission_this_month:    commission_month,
      commission_prev_month:    commission_prev,
      commission_total_ever:    commission_total,
      volume_transacted_month:  volume_month,
      volume_transacted_total:  volume_total,
      disponivel_count_month:   disp_count_month,
      disponivel_attended_month: disp_attended_month,
      disponivel_pct_of_total:  disp_pct,
      owners_with_disponivel:   owners_with_disp,
      owners_without_disponivel: owners_without_disp,
      average_ticket_brl:       avg_ticket
    }
  end

  def retention_metrics
    # Clientes com 1 único agendamento (one-and-done)
    one_timers = User.where(role: "client")
      .joins(:appointments)
      .where(appointments: { status: "attended" })
      .group("users.id")
      .having("COUNT(appointments.id) = 1")
      .count.size

    # Clientes recorrentes (2+ agendamentos atendidos)
    returning = User.where(role: "client")
      .joins(:appointments)
      .where(appointments: { status: "attended" })
      .group("users.id")
      .having("COUNT(appointments.id) >= 2")
      .count.size

    # Clientes sumidos (tiveram agendamentos mas nenhum nos últimos 45 dias)
    churned = User.where(role: "client")
      .joins(:appointments)
      .where(appointments: { status: "attended" })
      .where.not(id: Appointment.where(status: "attended").where("scheduled_at > ?", 45.days.ago).select(:user_id))
      .distinct.count

    # Owners inativos (cadastrados mas nunca receberam agendamento atendido)
    inactive_owners = CarWash
      .where(active: true)
      .where.not(id: Appointment.where(status: "attended").select(:car_wash_id))
      .count

    # No-show rate
    total_confirmed  = Appointment.where(status: %w[attended no_show]).count
    no_show_count    = Appointment.where(status: "no_show").count
    no_show_rate     = total_confirmed > 0 ? (no_show_count.to_f / total_confirmed * 100).round(1) : 0

    {
      clients_one_appointment:  one_timers,
      clients_returning:        returning,
      clients_churned_45d:      churned,
      inactive_owners:          inactive_owners,
      no_show_rate_pct:         no_show_rate,
      no_show_count:            no_show_count
    }
  end

  def supply_metrics
    # Lava-rápidos sem nenhum serviço cadastrado
    without_services = CarWash.where(active: true)
      .where.not(id: Service.select(:car_wash_id))
      .count

    # Sem horário de funcionamento
    without_hours = CarWash.where(active: true)
      .where.not(id: OperatingHour.select(:car_wash_id))
      .count

    # Ticket médio por lava-rápido
    avg_services_per_cw = Service.count.to_f / [CarWash.count, 1].max

    # Top 5 lava-rápidos por volume
    top_cws = CarWash.joins(appointments: :service)
      .where(appointments: { status: "attended" })
      .group("car_washes.id", "car_washes.name")
      .order(Arel.sql("SUM(services.price) DESC"))
      .limit(5)
      .pluck("car_washes.name", "SUM(services.price)", "COUNT(appointments.id)")
      .map { |name, rev, cnt| { name: name, revenue: rev.to_f.round(2), appointments: cnt.to_i } }

    # Concentração: % do volume no top 3
    total_vol = Appointment.where(status: "attended").joins(:service).sum("services.price").to_f
    top3_vol  = top_cws.first(3).sum { |c| c[:revenue] }
    concentration_pct = total_vol > 0 ? (top3_vol / total_vol * 100).round(1) : 0

    {
      active_car_washes_without_services: without_services,
      active_car_washes_without_hours:    without_hours,
      avg_services_per_car_wash:          avg_services_per_cw.round(1),
      top_5_car_washes:                   top_cws,
      revenue_concentration_top3_pct:     concentration_pct
    }
  end

  def support_metrics
    total_tickets   = SupportTicket.count
    open_tickets    = SupportTicket.where(status: "open").count
    in_progress     = SupportTicket.where(status: "in_progress").count
    resolved        = SupportTicket.where(status: "resolved").count

    # Categoria mais frequente
    top_category = SupportTicket
      .group(:category)
      .order(Arel.sql("COUNT(*) DESC"))
      .limit(1)
      .count.first&.first

    # Tempo médio de resolução (em horas)
    avg_resolution_h = SupportTicket
      .where(status: "resolved")
      .where.not(resolved_at: nil)
      .average("EXTRACT(EPOCH FROM (resolved_at - created_at)) / 3600")
      .to_f.round(1) rescue 0

    # Rascunhos do agente pendentes
    agent_drafts_pending = SupportTicket.where.not(agent_draft: nil).where(agent_sent: false).count

    {
      total_tickets:         total_tickets,
      open_tickets:          open_tickets,
      in_progress_tickets:   in_progress,
      resolved_tickets:      resolved,
      top_category:          top_category,
      avg_resolution_hours:  avg_resolution_h,
      agent_drafts_pending:  agent_drafts_pending
    }
  end

  def health_metrics
    # Agendamentos cancelados este mês
    cancelled_month = Appointment.where(status: "cancelled").where(created_at: @month_start..@month_end).count

    # Owners bloqueados
    blocked_owners = User.where(role: "owner").where.not(blocked_at: nil).count

    # Reviews médio geral
    avg_rating = Review.average(:rating).to_f.round(2) rescue 0
    total_reviews = Review.count rescue 0

    {
      cancelled_appointments_month: cancelled_month,
      blocked_owners:               blocked_owners,
      platform_avg_rating:          avg_rating,
      total_reviews:                total_reviews
    }
  end

  # ── PROMPT ───────────────────────────────────────────────────────────────

  def build_prompt(data, focus)
    focus_instruction = if focus.present?
      "\n\nFOCO SOLICITADO PELO CEO: #{focus}\nDê atenção especial a este tema, mas não ignore os outros se forem críticos."
    else
      ""
    end

    <<~PROMPT
      Você é o Chief Strategy Officer e advisor pessoal do CEO da Loov.

      A Loov é um marketplace brasileiro de agendamento de lava-rápidos — modelo similar ao iFood
      mas para serviços automotivos. O CEO é o único fundador, responsável por produto, tecnologia
      e estratégia simultaneamente. A empresa está em fase de testes com usuários reais.

      Modelo de negócio atual:
      - Agendamentos regulares: gratuitos para o lava-rápido (fase de testes)
      - Disponíveis (vagas de última hora): 5% de comissão sobre o valor do serviço
      - Receita atual vem exclusivamente dos Disponíveis

      Você acabou de receber o briefing completo e atualizado da plataforma:

      #{JSON.pretty_generate(data)}

      #{focus_instruction}

      Sua missão é entregar uma análise estratégica de alto nível — do tipo que um board de
      investidores de Série A espera ver. Pense como um advisor que já escalou marketplaces
      (Uber, Airbnb, iFood) e conhece os padrões de crescimento, os sinais de alerta e as
      alavancas de monetização de plataformas two-sided.

      Estruture sua resposta EXATAMENTE assim (use os títulos em maiúsculo):

      PULSO DA PLATAFORMA
      Em 3-4 frases, qual o estado real da Loov hoje. Seja honesto — não suavize problemas.

      OPORTUNIDADES CRÍTICAS (top 3)
      As 3 maiores alavancas de crescimento disponíveis AGORA com os dados que temos.
      Para cada uma: o que é, por que importa, e o impacto estimado em R$ ou % se executada.

      ALERTAS VERMELHOS
      O que pode matar o negócio ou travar o crescimento se não for endereçado nas próximas
      2 semanas. Seja direto e específico — cite números dos dados.

      MONETIZAÇÃO
      Análise do modelo atual + 2-3 formas concretas de aumentar receita nos próximos 90 dias
      sem grandes mudanças técnicas. Inclua estimativa de impacto.

      DECISÃO DESTA SEMANA
      UMA única ação — a mais importante que o CEO deve executar nos próximos 7 dias.
      Explique o raciocínio. Seja específico: o que fazer, como fazer, por que agora.

      VISÃO 90 DIAS
      Se as oportunidades críticas forem executadas, onde a Loov estaria em 90 dias?
      Métricas concretas: usuários, receita, volume transacionado.

      Tom: direto, sem eufemismos, sem enrolação. Você é um advisor pago para dizer a verdade,
      não para agradar. Use os dados reais — cite números específicos do briefing.
      Responda em português brasileiro.
    PROMPT
  end

  # ── CLAUDE API ───────────────────────────────────────────────────────────

  def call_claude(prompt)
    require "net/http"
    require "json"

    uri  = URI("https://api.anthropic.com/v1/messages")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.read_timeout = 120

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"]      = "application/json"
    request["x-api-key"]         = ENV["ANTHROPIC_API_KEY"]
    request["anthropic-version"] = "2023-06-01"

    request.body = {
      model:      "claude-sonnet  -4-6",
      max_tokens: 4096,
      messages:   [{ role: "user", content: prompt }]
    }.to_json

    response = http.request(request)
    body     = JSON.parse(response.body)
    raise "API error: #{body['error']&.dig('message')}" if body["error"]

    text = body.dig("content", 0, "text")
    { briefing: text, generated_at: Time.current.strftime("%d/%m/%Y %H:%M") }
  end
end
