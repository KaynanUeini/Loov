module Owner
  class AiInsightsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_owner

    def show
      car_wash = current_user.car_washes.first
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found if car_wash.nil?

      type     = params[:type]
      existing = AiInsight.current_for(car_wash)

      if existing && !cycle_expired?(existing)
        return render json: {
          insight:            existing.section(type) || "Análise não disponível para este período.",
          status:             existing.section_status(type),
          action_of_the_week: existing.action_of_the_week,
          generated_at:       existing.generated_at.strftime("%d/%m/%Y"),
          next_refresh:       next_cycle_date,
          days_remaining:     days_until_next_cycle,
          has_input:          existing.owner_input.present?,
          cycle_summary:      existing.cycle_summary,
          cached:             true
        }
      end

      render json: { needs_generation: true, days_remaining: 0 }
    end

    def analyze
      car_wash = current_user.car_washes.first
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found if car_wash.nil?

      type     = params[:type]
      force    = params[:force] == "true"
      existing = AiInsight.current_for(car_wash)

      if existing && !cycle_expired?(existing) && !force
        return render json: {
          insight:            existing.section(type),
          status:             existing.section_status(type),
          action_of_the_week: existing.action_of_the_week,
          generated_at:       existing.generated_at.strftime("%d/%m/%Y"),
          next_refresh:       next_cycle_date,
          days_remaining:     days_until_next_cycle,
          has_input:          existing.owner_input.present?,
          cycle_summary:      existing.cycle_summary,
          cached:             true
        }
      end

      previous_action = existing&.action_of_the_week
      existing&.archive_input!

      context         = build_context(car_wash)
      owner_input     = existing&.owner_input
      previous_inputs = existing&.previous_inputs_parsed || []
      prompt          = build_prompt(context, owner_input, previous_inputs, previous_action)

      begin
        raw_response = call_claude(prompt)
        sections     = parse_sections(raw_response)

        if existing
          existing.update!(content: sections.to_json, generated_at: Time.current)
        else
          existing = AiInsight.create!(
            car_wash:     car_wash,
            insight_type: "unified",
            content:      sections.to_json,
            generated_at: Time.current
          )
        end

        render json: {
          insight:            existing.section(type),
          status:             existing.section_status(type),
          action_of_the_week: sections["action_of_the_week"],
          generated_at:       existing.generated_at.strftime("%d/%m/%Y"),
          next_refresh:       next_cycle_date,
          days_remaining:     days_until_next_cycle,
          has_input:          false,
          cycle_summary:      sections["cycle_summary"],
          cached:             false
        }
      rescue => e
        Rails.logger.error("AI Insights error: #{e.message}")
        render json: { error: "Não foi possível gerar o insight agora." }, status: :unprocessable_entity
      end
    end

    def owner_input
      car_wash = current_user.car_washes.first
      existing = AiInsight.current_for(car_wash)
      return render json: { error: "Nenhuma análise encontrada." }, status: :not_found unless existing
      existing.update!(owner_input: params[:input], owner_input_at: Time.current)
      render json: { ok: true }
    end

    private

    def ensure_owner
      render json: { error: "Acesso negado." }, status: :forbidden unless current_user&.owner?
    end

    # ── CICLO ─────────────────────────────────────────────────────────────────

    def current_cycle_start
      today = Date.current
      today.day >= 15 ? Date.new(today.year, today.month, 15) : Date.new(today.year, today.month, 1)
    end

    def cycle_expired?(insight)
      insight.generated_at.to_date < current_cycle_start
    end

    def next_cycle_date
      today = Date.current
      if today.day < 15
        Date.new(today.year, today.month, 15).strftime("%d/%m/%Y")
      else
        (Date.new(today.year, today.month, 1) >> 1).strftime("%d/%m/%Y")
      end
    end

    def days_until_next_cycle
      (Date.parse(next_cycle_date) - Date.current).to_i
    end

    def cycle_type
      Date.current.day <= 14 ? "fechamento" : "acompanhamento"
    end

    # ── CLIMA ─────────────────────────────────────────────────────────────────

    def fetch_climate(lat, lon)
      return nil unless lat.present? && lon.present?

      today      = Date.current
      start_date = (today - 30).strftime("%Y-%m-%d")
      end_date   = today.strftime("%Y-%m-%d")

      uri  = URI("https://archive-api.open-meteo.com/v1/archive?latitude=#{lat}&longitude=#{lon}&start_date=#{start_date}&end_date=#{end_date}&daily=precipitation_sum&timezone=America%2FSao_Paulo")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true; http.read_timeout = 10

      data           = JSON.parse(http.get(uri.request_uri).body)
      precipitations = data.dig("daily", "precipitation_sum") || []
      rainy_days     = precipitations.count { |p| p.to_f > 5 }
      total_rain_mm  = precipitations.sum(&:to_f).round(1)

      {
        dias_de_chuva_ultimos_30_dias: rainy_days,
        total_chuva_mm:                total_rain_mm,
        periodo:                       "#{start_date} a #{end_date}",
        avaliacao_clima:               clima_label(rainy_days),
        perfil_clima:                  clima_perfil(rainy_days)
      }
    rescue => e
      Rails.logger.warn("Climate fetch failed: #{e.message}")
      nil
    end

    def clima_label(rainy_days)
      if    rainy_days >= 18 then "período muito chuvoso — impacto alto no movimento"
      elsif rainy_days >= 10 then "período moderadamente chuvoso — impacto médio no movimento"
      elsif rainy_days >= 4  then "clima favorável na maior parte do período"
      else                        "período seco — condições ideais para lava-rápido"
      end
    end

    def clima_perfil(rainy_days)
      if    rainy_days >= 18 then "muito_chuvoso"
      elsif rainy_days >= 10 then "chuvoso"
      else                        "favoravel"
      end
    end

    # ── FERIADOS ──────────────────────────────────────────────────────────────

    def upcoming_holidays
      today   = Date.current
      horizon = today + 15
      year    = today.year

      national = [
        [Date.new(year, 1,  1),  "Ano Novo"],
        [Date.new(year, 4, 21),  "Tiradentes"],
        [Date.new(year, 5,  1),  "Dia do Trabalho"],
        [Date.new(year, 9,  7),  "Independência"],
        [Date.new(year, 10, 12), "Nossa Senhora Aparecida"],
        [Date.new(year, 11,  2), "Finados"],
        [Date.new(year, 11, 15), "Proclamação da República"],
        [Date.new(year, 12, 25), "Natal"],
        [easter_date(year) - 49, "Carnaval (segunda)"],
        [easter_date(year) - 48, "Carnaval (terça)"],
        [easter_date(year) - 2,  "Sexta-feira Santa"],
        [easter_date(year),      "Páscoa"],
        [easter_date(year) + 60, "Corpus Christi"],
      ]

      if horizon.year > year
        national += national.map do |d, name|
          begin; [Date.new(year + 1, d.month, d.day), name]; rescue; nil; end
        end.compact
      end

      holidays_ahead = national.select { |d, _| d >= today && d <= horizon }
      return nil if holidays_ahead.empty?

      day_names = %w[Domingo Segunda Terça Quarta Quinta Sexta Sábado]
      holidays_ahead.map { |d, name| { data: d.strftime("%d/%m"), nome: name, dia: day_names[d.wday], dias_ate: (d - today).to_i } }
    end

    def easter_date(year)
      a = year % 19; b = year / 100; c = year % 100; d = b / 4; e = b % 4
      f = (b + 8) / 25; g = (b - f + 1) / 3; h = (19 * a + b - d - g + 15) % 30
      i = c / 4; k = c % 4; l = (32 + 2 * e + 2 * i - h - k) % 7
      m = (a + 11 * h + 22 * l) / 451
      month = (h + l - 7 * m + 114) / 31
      day   = ((h + l - 7 * m + 114) % 31) + 1
      Date.new(year, month, day)
    end

    # ── MARGEM ────────────────────────────────────────────────────────────────

    def fetch_margin_context(car_wash)
      margins = (0..2).map do |i|
        date = i.months.ago
        cost = car_wash.monthly_costs.find_by(year: date.year, month: date.month)
        next nil unless cost

        revenue    = car_wash.appointments
                       .where(status: "attended").joins(:service)
                       .where(scheduled_at: date.beginning_of_month..date.end_of_month)
                       .sum("services.price").to_f
        total_cost = cost.total.to_f
        profit     = revenue - total_cost
        margin     = revenue > 0 ? ((profit / revenue) * 100).round(1) : 0

        { mes: date.strftime("%b/%Y"), faturamento: revenue.round(2),
          custos: total_cost.round(2), lucro: profit.round(2), margem: margin }
      end.compact

      return nil if margins.empty?

      avg_margin    = (margins.map { |m| m[:margem] }.sum / margins.size).round(1)
      current_month = margins.first

      {
        historico_margem:   margins.reverse,
        margem_atual:       current_month[:margem],
        lucro_atual:        current_month[:lucro],
        custos_atual:       current_month[:custos],
        media_margem_3m:    avg_margin,
        perfil_financeiro:  margin_profile(avg_margin),
        tem_dados_de_custo: true
      }
    end

    def margin_profile(avg_margin)
      if    avg_margin >= 30 then "saudável"
      elsif avg_margin >= 10 then "apertado"
      elsif avg_margin >= 0  then "crítico"
      else                        "negativo"
      end
    end

    # ── OCIOSIDADE ────────────────────────────────────────────────────────────

    def calc_idle_loss(car_wash, base, ticket_medio)
      capacity = car_wash.capacity_per_slot.to_i
      return nil if capacity.zero?

      operating_hours   = car_wash.operating_hours
      avg_slots_per_day = if operating_hours.any?
        total_minutes = operating_hours.sum { |oh| begin; ((oh.closes_at - oh.opens_at) / 60).to_i; rescue; 480; end }
        ((total_minutes.to_f / operating_hours.size / 60) * capacity).round
      else
        capacity * 8
      end

      day_names   = %w[Domingo Segunda Terça Quarta Quinta Sexta Sábado]
      real_by_dow = base
        .where(scheduled_at: 30.days.ago..Time.current)
        .group(Arel.sql("EXTRACT(DOW FROM scheduled_at)::int"))
        .count

      idle_analysis = real_by_dow.map do |dow, count|
        avg_per_week  = (count.to_f / 4).round(1)
        idle_per_week = [avg_slots_per_day - avg_per_week, 0].max
        { dia: day_names[dow], media_atendimentos: avg_per_week,
          capacidade_estimada: avg_slots_per_day, buracos_estimados: idle_per_week,
          receita_perdida_semana: (idle_per_week * ticket_medio).round(2) }
      end

      total_lost = idle_analysis.sum { |d| d[:receita_perdida_semana] * 4 }.round(2)
      worst_day  = idle_analysis.max_by { |d| d[:receita_perdida_semana] }

      { analise_por_dia: idle_analysis, receita_perdida_mensal: total_lost,
        dia_mais_ocioso: worst_day&.dig(:dia), ticket_base: ticket_medio }
    end

    # ── MESMO PERÍODO ANO ANTERIOR ────────────────────────────────────────────

    def same_period_last_year(base)
      last_year_start = Date.current.beginning_of_month << 12
      last_year_end   = last_year_start.end_of_month

      revenue_ly = base.where(scheduled_at: last_year_start..last_year_end).sum("services.price").to_f
      count_ly   = base.where(scheduled_at: last_year_start..last_year_end).count
      return nil if count_ly.zero?

      { mes_referencia: last_year_start.strftime("%b/%Y"), faturamento: revenue_ly.round(2),
        agendamentos: count_ly, ticket_medio: count_ly > 0 ? (revenue_ly / count_ly).round(2) : 0 }
    end

    # ── PADRÃO DE ABANDONO ────────────────────────────────────────────────────

    def detect_abandonment_pattern(car_wash)
      all_appts       = car_wash.appointments.where(status: "attended").joins(:user)
      visits_per_user = all_appts.group(:user_id).count
      single_users    = visits_per_user.select { |_, c| c == 1 }.keys
      return nil if single_users.empty?

      first_dates = all_appts.where(user_id: single_users).group(:user_id).minimum(:scheduled_at)
      by_month    = first_dates.group_by { |_, d| d.strftime("%Y-%m") }
        .map { |m, e| { mes: m, clientes_unica_visita: e.count } }
        .sort_by { |e| e[:mes] }.last(6)

      peak = by_month.max_by { |e| e[:clientes_unica_visita] }
      { abandono_por_mes: by_month, mes_maior_abandono: peak&.dig(:mes), pico_abandono: peak&.dig(:clientes_unica_visita) }
    rescue => e
      Rails.logger.warn("Abandonment pattern error: #{e.message}"); nil
    end

    # ── CONTEXTO PRINCIPAL ────────────────────────────────────────────────────

    def build_context(car_wash)
      base = car_wash.appointments.where(status: "attended").joins(:service)

      upcoming_confirmed = car_wash.appointments
        .where(status: "confirmed")
        .where(scheduled_at: Time.current..30.days.from_now)
        .count

      upcoming_7d = car_wash.appointments
        .where(status: "confirmed")
        .where(scheduled_at: Time.current..7.days.from_now)
        .joins(:service)
        .sum("services.price").to_f

      total_sales        = base.sum("services.price").to_f
      total_appointments = base.count
      ticket_medio       = total_appointments > 0 ? (total_sales / total_appointments).round(2) : 0

      monthly = (0..5).map do |i|
        sd      = i.months.ago.beginning_of_month
        ed      = i.months.ago.end_of_month
        period  = base.where(scheduled_at: sd..ed)
        revenue = period.sum("services.price").to_f
        count   = period.count
        { mes: sd.strftime("%Y-%m"), mes_label: sd.strftime("%b/%Y"),
          faturamento: revenue.round(2), agendamentos: count,
          valor_medio_por_atendimento: count > 0 ? (revenue / count).round(2) : 0 }
      end.reverse

      last_30         = base.where(scheduled_at: 30.days.ago..Time.current)
      prev_30         = base.where(scheduled_at: 60.days.ago..30.days.ago)
      last_30_revenue = last_30.sum("services.price").to_f
      prev_30_revenue = prev_30.sum("services.price").to_f
      last_30_count   = last_30.count
      prev_30_count   = prev_30.count
      revenue_growth  = prev_30_revenue > 0 ? (((last_30_revenue / prev_30_revenue) - 1) * 100).round(1) : nil

      day_names     = %w[Domingo Segunda Terça Quarta Quinta Sexta Sábado]
      demand_by_dow = base
        .group(Arel.sql("EXTRACT(DOW FROM scheduled_at)::int"))
        .order(Arel.sql("EXTRACT(DOW FROM scheduled_at)::int"))
        .count
        .map { |dow, count| { dia: day_names[dow], agendamentos: count } }

      best_day  = demand_by_dow.max_by { |d| d[:agendamentos] }
      worst_day = demand_by_dow.min_by { |d| d[:agendamentos] }

      peak_hours = base
        .group(Arel.sql("EXTRACT(HOUR FROM scheduled_at)::int"))
        .order(Arel.sql("count_all DESC")).limit(3).count
        .map { |hour, count| "#{hour}h (#{count} atendimentos)" }

      hourly_counts = base.group(Arel.sql("EXTRACT(HOUR FROM scheduled_at)::int")).count
      avg_hourly    = hourly_counts.values.sum.to_f / [hourly_counts.size, 1].max
      idle_hours    = hourly_counts.select { |_, c| c < avg_hourly * 0.4 }.map { |h, c| "#{h}h (#{c} atendimentos)" }

      services_perf = base
        .group("services.title")
        .select("services.title, COUNT(*) AS total_count, SUM(services.price) AS total_revenue")
        .order(Arel.sql("total_revenue DESC"))
        .map do |s|
          last_m   = base.joins(:service).where(services: { title: s.title }, scheduled_at: 30.days.ago..Time.current).count
          prev_m   = base.joins(:service).where(services: { title: s.title }, scheduled_at: 60.days.ago..30.days.ago).count
          variacao = prev_m > 0 ? (((last_m.to_f / prev_m) - 1) * 100).round(1) : nil
          { servico: s.title, total_atendimentos: s.total_count.to_i,
            receita_total: s.total_revenue.to_f.round(2),
            valor_por_atendimento: s.total_count > 0 ? (s.total_revenue.to_f / s.total_count).round(2) : 0,
            atendimentos_ultimo_mes: last_m, atendimentos_mes_anterior: prev_m,
            variacao_volume: variacao ? "#{variacao}%" : "sem dados" }
        end

      price_changes = base.joins(:service).group("services.title")
        .pluck("services.title, MIN(services.price), MAX(services.price)")
        .map { |t, mn, mx| { servico: t, preco_minimo: mn.to_f, preco_maximo: mx.to_f, houve_aumento: mx.to_f > mn.to_f } }

      client_counts     = base.group(:user_id).count
      recurring_clients = client_counts.count { |_, c| c > 1 }
      new_clients_count = client_counts.count { |_, c| c == 1 }
      total_clients     = client_counts.size
      retention_rate    = total_clients > 0 ? ((recurring_clients.to_f / total_clients) * 100).round(1) : 0
      avg_visits        = recurring_clients > 0 ? (client_counts.select { |_, c| c > 1 }.values.sum.to_f / recurring_clients).round(1) : 0

      top_clients = base.joins(:user).group("users.email")
        .order(Arel.sql("count_all DESC")).limit(5).count
        .map { |email, count| { cliente: email.split("@").first.capitalize, visitas: count } }

      all_last_visit = car_wash.appointments.where(status: "attended")
        .joins(:user).group("users.email").maximum(:scheduled_at)

      at_risk = all_last_visit
        .select { |_, last| last < 30.days.ago && last > 90.days.ago }
        .sort_by { |_, last| last }.first(10)
        .map { |email, last| { cliente: email.split("@").first.capitalize, dias_sem_visita: (Time.current - last).to_i / 1.day } }

      lost_clients = all_last_visit.count { |_, last| last < 90.days.ago }

      first_visits = car_wash.appointments.where(status: "attended")
        .joins(:user).group("users.id").minimum(:scheduled_at)

      new_by_month = first_visits
        .group_by { |_, d| d.strftime("%Y-%m") }
        .map { |month, entries| { mes: month, novos_clientes: entries.count } }
        .sort_by { |e| e[:mes] }.last(6)

      prev_month_new = first_visits.count { |_, d| d >= 60.days.ago && d < 30.days.ago }
      this_month_new = first_visits.count { |_, d| d >= 30.days.ago }
      growth_rate    = prev_month_new > 0 ? (((this_month_new.to_f / prev_month_new) - 1) * 100).round(1) : nil

      total_past    = car_wash.appointments.where("scheduled_at < ?", Time.current).where.not(status: "cancelled").count
      total_no_show = car_wash.appointments.where(status: "no_show").count
      no_show_rate  = total_past > 0 ? ((total_no_show.to_f / total_past) * 100).round(1) : 0

      {
        data_atual:                      Time.current.strftime("%d/%m/%Y"),
        dia_do_mes_atual:                Date.current.day,
        tipo_de_ciclo:                   cycle_type,
        mes_atual:                       Time.current.strftime("%B de %Y"),
        nome:                            car_wash.name,
        localizacao:                     car_wash.location_context.presence || "não informada",
        bairro:                          car_wash.bairro,
        cidade:                          car_wash.cidade,
        uf:                              car_wash.uf,
        clima_ultimos_30_dias:           fetch_climate(car_wash.latitude, car_wash.longitude),
        feriados_proximos_15_dias:       upcoming_holidays,
        saude_financeira:                fetch_margin_context(car_wash),
        ociosidade:                      calc_idle_loss(car_wash, base, ticket_medio),
        mesmo_periodo_ano_anterior:      same_period_last_year(base),
        padrao_abandono:                 detect_abandonment_pattern(car_wash),
        faturamento_total:               total_sales.round(2),
        faturamento_ultimos_30_dias:     last_30_revenue.round(2),
        faturamento_30_60_dias:          prev_30_revenue.round(2),
        variacao_faturamento_mensal:     revenue_growth ? "#{revenue_growth}%" : "sem dados",
        atendimentos_30_dias:            last_30_count,
        atendimentos_30_60_dias:         prev_30_count,
        valor_medio_por_atendimento:     ticket_medio,
        historico_6_meses:               monthly,
        taxa_no_show:                    "#{no_show_rate}%",
        agendamentos_confirmados_proximos_30_dias: upcoming_confirmed,
        receita_projetada_proximos_7_dias:         upcoming_7d.round(2),
        variacao_precos_por_servico:     price_changes,
        percentual_clientes_que_voltam:  "#{retention_rate}%",
        media_visitas_cliente_fiel:      avg_visits,
        total_clientes:                  total_clients,
        clientes_que_voltaram:           recurring_clients,
        clientes_que_vieram_so_uma_vez:  new_clients_count,
        melhor_dia:                      best_day,
        pior_dia:                        worst_day,
        horarios_mais_movimentados:      peak_hours,
        horarios_ociosos:                idle_hours,
        movimento_por_dia_da_semana:     demand_by_dow,
        servicos:                        services_perf,
        clientes_mais_frequentes:        top_clients,
        clientes_sumidos_30_a_90_dias:   at_risk,
        clientes_perdidos_mais_90_dias:  lost_clients,
        novos_clientes_este_mes:         this_month_new,
        novos_clientes_mes_anterior:     prev_month_new,
        variacao_novos_clientes:         growth_rate ? "#{growth_rate}%" : "sem dados",
        novos_clientes_por_mes:          new_by_month
      }
    end

    # ── PROMPT ────────────────────────────────────────────────────────────────

    def build_prompt(ctx, owner_input = nil, previous_inputs = [], previous_action = nil)
      tipo = ctx[:tipo_de_ciclo]

      cycle_instruction = if tipo == "fechamento"
        <<~CYCLE
          ═══ TIPO DE CICLO: FECHAMENTO DO MÊS ANTERIOR ══════════════════════
          Hoje é dia #{ctx[:dia_do_mes_atual]}. Este é o ciclo de FECHAMENTO.
          FOCO: avaliar o mês que terminou com números finais — não parciais.
          Compare com o mesmo mês do ano anterior e com o mês imediatamente anterior.
          Identifique o que funcionou, o que falhou e por quê com base nos dados.
          Para o mês atual (início): projete o mês completo com base nos agendamentos confirmados e no ritmo histórico.
          A action_of_the_week deve atacar o maior problema identificado no fechamento.
        CYCLE
      else
        <<~CYCLE
          ═══ TIPO DE CICLO: ACOMPANHAMENTO DO MÊS EM CURSO ══════════════════
          Hoje é dia #{ctx[:dia_do_mes_atual]}. Este é o ciclo de ACOMPANHAMENTO.
          FOCO: o mês está pela metade — dados são PARCIAIS.
          Projete o mês completo multiplicando o ritmo atual pelos dias restantes.
          Compare o ritmo atual com o mesmo período do mês anterior (não compare total parcial com total completo sem avisar).
          Destaque o que já está bem encaminhado e o que precisa de correção urgente para fechar bem o mês.
          A action_of_the_week deve ser algo executável ainda neste mês que mova o número.
        CYCLE
      end

      input_block = owner_input.present? ? <<~INPUT
        O DONO REPORTOU O SEGUINTE SOBRE O PERÍODO:
        #{owner_input}
        Cruze o que ele reportou com os números. Se funcionou, confirme com dados e aprofunde. Se não funcionou, explique com base nos números e sugira outro caminho. Não elogie o esforço — avalie o resultado.
      INPUT
      : "O dono não registrou nenhuma ação neste ciclo."

      history_block = previous_inputs.any? ? <<~HISTORY
        CICLOS ANTERIORES (use para não repetir sugestões já dadas):
        #{previous_inputs.map.with_index { |inp, i| "Ciclo -#{i+1} (#{inp['saved_at']}): #{inp['text']}" }.join("\n")}
      HISTORY
      : ""

      validation_block = previous_action.present? ? <<~VALIDATION
        A AÇÃO SUGERIDA NO CICLO ANTERIOR FOI:
        "#{previous_action}"
        OBRIGATÓRIO: comece o campo "cycle_summary" avaliando se essa ação teve impacto nos dados. Se o indicador melhorou, confirme com números concretos. Se não houve impacto, diga com clareza e mude a abordagem. Nunca use a frase "os números falam por si".
      VALIDATION
      : ""

      climate_instruction = if ctx[:clima_ultimos_30_dias]
        c = ctx[:clima_ultimos_30_dias]
        case c[:perfil_clima]
        when "muito_chuvoso"
          "ATENÇÃO CLIMA: nos últimos 30 dias corridos (#{c[:periodo]}) foram #{c[:dias_de_chuva_ultimos_30_dias]} dias com chuva significativa (#{c[:total_chuva_mm]}mm). Esse período cruza dois meses — não diga '#{c[:dias_de_chuva_ultimos_30_dias]} dias de chuva este mês'. Se faturamento caiu, o clima é fator relevante. Foque em serviços internos: higienização, ar-condicionado, couro e plásticos."
        when "chuvoso"
          "CLIMA: #{c[:dias_de_chuva_ultimos_30_dias]} dias de chuva nos últimos 30 dias (#{c[:periodo]}, #{c[:total_chuva_mm]}mm). Período cruza dois meses — seja preciso ao citar o dado."
        else
          "CLIMA: favorável nos últimos 30 dias (#{c[:dias_de_chuva_ultimos_30_dias]} dias de chuva). Queda de movimento não tem justificativa climática relevante."
        end
      else
        ""
      end

      holiday_instruction = if ctx[:feriados_proximos_15_dias]&.any?
        feriados = ctx[:feriados_proximos_15_dias].map { |h| "#{h[:nome]} (#{h[:dia]}, #{h[:data]}, em #{h[:dias_ate]} dias)" }.join(", ")
        "FERIADOS NOS PRÓXIMOS 15 DIAS: #{feriados}. Alerte o dono para antecipar o pico — o dia anterior costuma ter movimento alto. Se feriado prolongado, sugira combo de preparação do carro para viagem."
      else
        ""
      end

      idle_instruction = if ctx[:ociosidade] && ctx[:ociosidade][:receita_perdida_mensal].to_f > 0
        o = ctx[:ociosidade]
        "DINHEIRO DEIXADO NA MESA: estimativa de R$ #{o[:receita_perdida_mensal]} em receita perdida por ociosidade nos últimos 30 dias. Dia mais ocioso: #{o[:dia_mais_ocioso]}. Use esse número na análise de demanda."
      else
        ""
      end

      margin_instruction = if ctx[:saude_financeira]
        m = ctx[:saude_financeira]
        case m[:perfil_financeiro]
        when "saudável"
          "SAÚDE FINANCEIRA — SAUDÁVEL: margem #{m[:margem_atual]}% este mês, média #{m[:media_margem_3m]}% nos últimos 3 meses, lucro R$ #{m[:lucro_atual]}. Negócio TEM capacidade de investir. A action_of_the_week pode ser EXPANSÃO."
        when "apertado"
          "SAÚDE FINANCEIRA — APERTADA: margem #{m[:margem_atual]}%, lucro R$ #{m[:lucro_atual]}. Baixo custo com retorno rápido. Investimento máximo R$ 200 com impacto claro. A action_of_the_week deve ser OTIMIZAÇÃO."
        when "crítico"
          "SAÚDE FINANCEIRA — CRÍTICA: margem #{m[:margem_atual]}%, lucro R$ #{m[:lucro_atual]}. Aumentar receita com o que já existe. A action_of_the_week deve ser CAIXA RÁPIDO — algo que gere receita em 48h."
        when "negativo"
          "SAÚDE FINANCEIRA — NEGATIVA: prejuízo de R$ #{m[:lucro_atual].abs}. Zero investimentos novos. A action_of_the_week deve ser SOBREVIVÊNCIA — específica e diferente a cada ciclo."
        else
          "SAÚDE FINANCEIRA: margem #{m[:margem_atual]}%, lucro R$ #{m[:lucro_atual]}."
        end
      else
        "SAÚDE FINANCEIRA: custos não cadastrados. Sugira ações equilibradas e encoraje o dono a cadastrar os custos mensais."
      end

      perfil_bairro = case ctx[:bairro].to_s.downcase
      when /paulista|jardins|itaim|moema|pinheiros|vila nova conceição|brooklin/
        "área nobre — cliente valoriza qualidade acima do preço. Upselling tem alta aceitação."
      when /centro|brás|bom retiro|pari|cambuci/
        "área comercial densa — foque em agilidade, volume e preço competitivo."
      when /zona sul|campo limpo|capão redondo|m'boi mirim|grajaú/
        "área popular — preço acessível, volume e fidelização simples."
      else
        "analise o perfil da região pela localização e adapte ao poder aquisitivo local."
      end

      <<~PROMPT
        Você é um consultor especialista em lava-rápidos no Brasil. Direto, pé no chão, linguagem simples.

        #{cycle_instruction}

        ═══ CONTEXTO FIXO ═══════════════════════════════════════════════════
        DATA DE HOJE: #{ctx[:data_atual]} (dia #{ctx[:dia_do_mes_atual]} do mês).

        IMPORTANTE SOBRE OS DADOS: todos os valores de faturamento, receita e atendimentos referem-se EXCLUSIVAMENTE a clientes que compareceram (status "attended"). Agendamentos futuros aparecem separadamente como projeção — não some projeção com histórico.

        PROJEÇÃO FUTURA: #{ctx[:agendamentos_confirmados_proximos_30_dias]} agendamentos confirmados nos próximos 30 dias (receita potencial de R$ #{ctx[:receita_projetada_proximos_7_dias]} nos próximos 7 dias se todos comparecerem). Taxa de no-show atual: #{ctx[:taxa_no_show]}.

        PRODUTO: app de agendamento online. NUNCA sugira nada sobre agendamento ou marcação.
        CLIENTE FINAL: não faz nada. Nunca sugira pedir indicação, avaliação ou feedback.

        ═══ SINAIS DO PERÍODO ═══════════════════════════════════════════════
        #{climate_instruction}
        #{holiday_instruction}
        #{idle_instruction}

        ═══ SAÚDE FINANCEIRA ════════════════════════════════════════════════
        #{margin_instruction}

        ═══ PERFIL DO MERCADO ═══════════════════════════════════════════════
        REGIÃO (#{ctx[:bairro]}, #{ctx[:cidade]}): #{perfil_bairro}

        ═══ REGRAS DE ANÁLISE ═══════════════════════════════════════════════
        PREÇO: se preço já subiu, não sugira novo aumento — sugira premiumização.
        UPSELLING: cliente com carro parado é o momento mais valioso.
        MESMO PERÍODO ANO ANTERIOR: use para diferenciar sazonalidade de queda de gestão.
        PADRÃO DE ABANDONO: pico de visita única pode indicar promoção que atraiu público errado.

        ═══ REGRAS DA ACTION_OF_THE_WEEK ════════════════════════════════════
        1. NUNCA repita a ação do ciclo anterior.
        2. NUNCA use "mande mensagem para clientes" como ação — se usar contato, especifique exatamente o que falar, qual oferta e retorno esperado em reais.
        3. Ataque a MAIOR alavanca dos dados.
        4. ESPECÍFICO: nome do serviço, valor, dia, horário, estimativa de retorno em reais.
        5. Executável HOJE ou AMANHÃ.
        6. Varie o tipo: operacional, comercial, precificação, mix, eficiência de custo.

        ═══ REGRAS DE ESCRITA ═══════════════════════════════════════════════
        1. Linguagem de conversa, sem termos técnicos.
        2. Comece pelo que melhorou.
        3. Mês incompleto: deixe claro e projete o mês completo.
        4. Compare com mês anterior E mesmo período do ano passado quando disponível.
        5. Cada seção ataca problema diferente — sem repetição.
        6. Máximo 3 parágrafos por seção. Sem listas ou títulos dentro do texto.
        7. NUNCA use "os números falam por si".
        8. NUNCA corte uma frase no meio.
        9. Responda SOMENTE em JSON válido.

        #{validation_block}

        ═══ DADOS DO NEGÓCIO ════════════════════════════════════════════════
        #{ctx[:nome]} — #{ctx[:localizacao]}
        #{ctx.to_json}

        ═══ INPUT DO DONO ═══════════════════════════════════════════════════
        #{input_block}
        #{history_block}

        ═══ FORMATO DE RESPOSTA (JSON EXATO) ════════════════════════════════
        {
          "sales":     { "text": "faturamento real com comparativo e projeção se mês parcial", "status": "up|down|stable" },
          "services":  { "text": "serviços com evolução, upselling e premiumização", "status": "up|down|stable" },
          "clients":   { "text": "retenção, visita única e padrão de abandono", "status": "up|down|stable" },
          "demand":    { "text": "pico, ociosidade e dinheiro deixado na mesa com valor estimado", "status": "up|down|stable" },
          "retention": { "text": "clientes sumidos com nomes e ação concreta", "status": "up|down|stable" },
          "growth":    { "text": "novos clientes, feriados próximos e visibilidade", "status": "up|down|stable" },
          "cycle_summary": "valida ação anterior com dados se houver. Resumo do momento em 2 frases.",
          "action_of_the_week": "ação única, específica, executável hoje ou amanhã — com serviço, valor estimado de retorno, calibrada pela saúde financeira."
        }
      PROMPT
    end

    # ── PARSE / CALL ──────────────────────────────────────────────────────────

    def parse_sections(raw)
      clean = raw.gsub(/```json|```/, "").strip
      JSON.parse(clean)
    rescue => e
      Rails.logger.error("Parse error: #{e.message} — raw: #{raw[0..200]}")
      fallback = { "text" => raw, "status" => "stable" }
      { "sales" => fallback, "services" => fallback, "clients" => fallback,
        "demand" => fallback, "retention" => fallback, "growth" => fallback,
        "cycle_summary" => "", "action_of_the_week" => "" }
    end

    def call_claude(prompt)
      require "net/http"
      require "json"

      uri  = URI("https://api.anthropic.com/v1/messages")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true; http.read_timeout = 120

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"]      = "application/json"
      request["x-api-key"]         = ENV["ANTHROPIC_API_KEY"]
      request["anthropic-version"] = "2023-06-01"

      request.body = {
        model:      "claude-sonnet-4-6",
        max_tokens: 4000,
        system:     "Você é um consultor especialista em lava-rápidos no Brasil. Direto, simples, sem termos técnicos. Nunca sugere nada sobre agendamento. Nunca pede nada ao cliente final. Faturamento = apenas clientes que compareceram (attended). Calibra investimentos pela margem real. Dados de clima são dos últimos 30 dias corridos. Nunca usa 'os números falam por si'. Action_of_the_week é sempre específica. Usa os dados reais do banco naturalmente na análise quando relevantes — não lista todos os indicadores. Responde SEMPRE em JSON válido exatamente no formato solicitado.",
        messages:   [{ role: "user", content: prompt }]
      }.to_json

      response = http.request(request)
      body     = JSON.parse(response.body)
      raise "API error: #{body['error']&.dig('message')}" if body["error"]
      body.dig("content", 0, "text") || "{}"
    end
  end
end
