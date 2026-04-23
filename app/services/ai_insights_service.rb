require "net/http"
require "json"

# Encapsula toda a lógica de geração de análise de IA.
# Usado pelo AiInsightsJob (assíncrono) e pelo controller (leitura de cache).
class AiInsightsService
  def initialize(car_wash)
    @car_wash = car_wash
  end

  MODEL = "claude-sonnet-4-6".freeze

  # Ponto de entrada. Retorna um trace completo — não só as seções — pra que o
  # caller possa persistir observabilidade de cada execução (prompt, resposta
  # bruta, tokens, latência, flags de crise) mesmo em caso de falha.
  #
  # Retorno:
  #   {
  #     status:         "success" | "parse_fallback" | "api_error",
  #     sections:       {...} | nil,           # hash parseado ou fallback
  #     prompt:         "...",                 # prompt exato enviado
  #     raw_response:   "..." | nil,           # texto do Claude (nil se API falhou)
  #     model:          "claude-sonnet-4-6",
  #     cycle_type:     "fechamento" | "acompanhamento",
  #     is_crisis_mode: true | false,
  #     owner_input:    "..." | nil,
  #     input_tokens:   Integer | nil,
  #     output_tokens:  Integer | nil,
  #     latency_ms:     Integer | nil,
  #     parse_ok:       true | false,
  #     parse_error:    "..." | nil,
  #     error_message:  "..." | nil            # apenas quando status != success
  #   }
  def generate(previous_action: nil, owner_input: nil, previous_inputs: [])
    context        = build_context
    is_crisis_mode = context.dig(:saude_financeira, :is_critical_state) || false
    cycle_type     = context[:tipo_de_ciclo]
    prompt         = build_prompt(context, owner_input, previous_inputs, previous_action)

    api_result = call_claude(prompt)
    trace = {
      prompt:         prompt,
      model:          MODEL,
      cycle_type:     cycle_type,
      is_crisis_mode: is_crisis_mode,
      owner_input:    owner_input,
      raw_response:   api_result[:raw],
      input_tokens:   api_result[:input_tokens],
      output_tokens:  api_result[:output_tokens],
      latency_ms:     api_result[:latency_ms],
    }

    if api_result[:error]
      return trace.merge(
        status:        "api_error",
        sections:      nil,
        parse_ok:      false,
        parse_error:   nil,
        error_message: api_result[:error],
      )
    end

    parsed = parse_sections(api_result[:raw])
    trace.merge(
      status:        parsed[:ok] ? "success" : "parse_fallback",
      sections:      parsed[:sections],
      parse_ok:      parsed[:ok],
      parse_error:   parsed[:error],
      error_message: nil,
    )
  end

  private

  attr_reader :car_wash

  # ── CICLO ─────────────────────────────────────────────────────────────────────

  def current_cycle_start
    today = Date.current
    today.day >= 15 ? Date.new(today.year, today.month, 15) : Date.new(today.year, today.month, 1)
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

  # ── CLIMA ─────────────────────────────────────────────────────────────────────

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

  # ── FERIADOS ──────────────────────────────────────────────────────────────────

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

  # ── MARGEM E REFERÊNCIA HISTÓRICA ─────────────────────────────────────────────
  # Sem benchmarks de setor — não temos estudo vetado pra lava-rápido no Brasil
  # que justifique "aluguel ideal 18%" ou "salários 25–35%". A referência é o
  # próprio histórico do negócio, comparando o mês atual com a média dos meses
  # anteriores (até 6) pra detectar desvios estruturais.

  def fetch_margin_context
    # Atual + 6 meses anteriores. Historical = margins[1..], excluindo o mês em curso.
    margins = (0..6).map do |i|
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

      cost_breakdown = {
        aluguel:      cost.rent.to_f,
        salarios:     cost.salaries.to_f,
        agua_luz:     cost.utilities.to_f,
        produtos:     cost.products.to_f,
        manutencao:   cost.maintenance.to_f,
        outros_fixos: cost.other_fixed.to_f,
        outros_var:   cost.other_variable.to_f
      }

      cost_pct = cost_breakdown.transform_values do |v|
        revenue > 0 ? (v / revenue * 100).round(1) : 0
      end

      { mes: date.strftime("%b/%Y"), faturamento: revenue.round(2),
        custos: total_cost.round(2), lucro: profit.round(2), margem: margin,
        detalhamento_custos: cost_breakdown, percentual_custos: cost_pct }
    end.compact

    return nil if margins.empty?

    # Recorte explícito para as estatísticas já existentes (3 meses mais recentes).
    three_month_slice = margins.first([margins.size, 3].min)
    avg_margin        = (three_month_slice.map { |m| m[:margem] }.sum / three_month_slice.size).round(1)
    current_month     = margins.first

    ticket_medio = car_wash.appointments
      .where(status: "attended").joins(:service)
      .where(scheduled_at: 90.days.ago..Time.current)
      .average("services.price").to_f.round(2)

    custos_fixos_mes = current_month.dig(:detalhamento_custos, :aluguel).to_f  +
                       current_month.dig(:detalhamento_custos, :salarios).to_f +
                       current_month.dig(:detalhamento_custos, :agua_luz).to_f +
                       current_month.dig(:detalhamento_custos, :outros_fixos).to_f

    meses_anteriores_3m = three_month_slice[1..] || []
    media_custos_fixos_3m = if meses_anteriores_3m.any?
      custos_anteriores = meses_anteriores_3m.map do |m|
        m.dig(:detalhamento_custos, :aluguel).to_f  +
        m.dig(:detalhamento_custos, :salarios).to_f +
        m.dig(:detalhamento_custos, :agua_luz).to_f +
        m.dig(:detalhamento_custos, :outros_fixos).to_f
      end
      (custos_anteriores.sum.to_f / [custos_anteriores.size, 1].max).round(2)
    else
      0.0
    end

    custos_suspeitos = media_custos_fixos_3m > 0.0 &&
                       Date.current.day < 28 &&
                       custos_fixos_mes < (media_custos_fixos_3m * 0.60)

    break_even_atendimentos = ticket_medio > 0 ? (current_month[:custos].to_f / ticket_medio).ceil : nil

    atendimentos_mes_atual = car_wash.appointments
      .where(status: "attended")
      .where(scheduled_at: Time.current.beginning_of_month..Time.current)
      .count

    atendimentos_faltam = break_even_atendimentos ? [break_even_atendimentos - atendimentos_mes_atual, 0].max : nil

    # ── Referência histórica (o próprio negócio, últimos 6 meses) ──────────────
    historico_meses        = margins[1..] || []                    # exclui o mês atual
    meses_de_historico     = historico_meses.size
    historico_suficiente   = meses_de_historico >= 3               # mínimo pra média confiável
    mes_corrente_completo  = Date.current.day >= 28                # evita distorção por receita parcial
    alertas_disponiveis    = historico_suficiente && mes_corrente_completo
    threshold_pp           = 3.0                                   # desvio de +3pp vs média = alerta

    pct_media_historica = if historico_suficiente
      {
        aluguel:      media_pct(historico_meses, :aluguel),
        salarios:     media_pct(historico_meses, :salarios),
        produtos:     media_pct(historico_meses, :produtos),
        agua_luz:     media_pct(historico_meses, :agua_luz),
        manutencao:   media_pct(historico_meses, :manutencao),
        outros_fixos: media_pct(historico_meses, :outros_fixos),
        outros_var:   media_pct(historico_meses, :outros_var),
      }
    end

    alertas_custo = []
    pct = current_month[:percentual_custos]

    if alertas_disponiveis && pct_media_historica
      %i[aluguel salarios produtos].each do |linha|
        atual = pct[linha].to_f
        media = pct_media_historica[linha].to_f
        next if media.zero?
        delta_pp = (atual - media).round(1)
        next if delta_pp < threshold_pp

        impacto = (delta_pp / 100.0 * current_month[:faturamento]).round(2)
        alertas_custo << {
          linha:                           linha.to_s,
          pct_atual:                       atual,
          pct_media_historica:             media,
          meses_de_historico:              meses_de_historico,
          delta_pp:                        delta_pp,
          impacto_mensal_se_voltar_a_media: impacto,
          referencia:                      "historico_proprio_negocio",
          mensagem: "#{linha.to_s.capitalize} em #{atual}% da receita — média dos últimos #{meses_de_historico} meses fechados: #{media}%. Voltar à média representa R$ #{impacto}/mês a mais no resultado. Referência: histórico do próprio negócio."
        }
      end
    end

    custos_estaveis_vs_historico = alertas_disponiveis && alertas_custo.empty? &&
                                   current_month[:detalhamento_custos].values.any? { |v| v.to_f > 0 }

    is_critical = current_month[:faturamento] > 0 &&
                  current_month[:lucro] < 0 &&
                  current_month[:lucro].abs >= current_month[:faturamento] * 0.5

    media_fat_3m   = three_month_slice.map { |m| m[:faturamento] }.sum.to_f / [three_month_slice.size, 1].max
    aluguel_atual  = current_month.dig(:detalhamento_custos, :aluguel).to_f
    salarios_atual = current_month.dig(:detalhamento_custos, :salarios).to_f

    {
      historico_margem:                margins.reverse,
      margem_atual:                    current_month[:margem],
      lucro_atual:                     current_month[:lucro],
      custos_atual:                    current_month[:custos],
      custos_fixos_estimados:          custos_fixos_mes.round(2),
      media_custos_fixos_historica:    media_custos_fixos_3m,
      detalhamento_custos:             current_month[:detalhamento_custos],
      percentual_custos:               current_month[:percentual_custos],
      media_margem_3m:                 avg_margin,
      media_faturamento_3m:            media_fat_3m.round(2),
      perfil_financeiro:               margin_profile(avg_margin),
      is_critical_state:               is_critical,
      custos_suspeitos:                custos_suspeitos,
      break_even_atendimentos:         break_even_atendimentos,
      break_even_pode_estar_subestimado: custos_suspeitos,
      atendimentos_para_break_even:    atendimentos_faltam,
      atendimentos_realizados_mes:     atendimentos_mes_atual,
      ticket_medio_90d:                ticket_medio,
      alertas_custo:                   alertas_custo,
      custos_estaveis_vs_historico:    custos_estaveis_vs_historico,
      aluguel_atual:                   aluguel_atual,
      salarios_atual:                  salarios_atual,
      # Referência para o prompt: a comparação é com o próprio histórico, não com
      # benchmark de setor. Essas chaves deixam isso explícito para o LLM.
      referencia_origem:               "historico_proprio_negocio",
      referencia_meses:                meses_de_historico,
      referencia_suficiente:           historico_suficiente,
      referencia_mes_completo:         mes_corrente_completo,
      referencia_threshold_pp:         threshold_pp,
      pct_media_historica:             pct_media_historica,
      tem_dados_de_custo:              true
    }
  end

  def media_pct(meses, linha)
    valores = meses.map { |m| m.dig(:percentual_custos, linha).to_f }
    return 0.0 if valores.empty?
    (valores.sum / valores.size).round(1)
  end

  def margin_profile(avg_margin)
    if    avg_margin >= 30 then "saudável"
    elsif avg_margin >= 10 then "apertado"
    elsif avg_margin >= 0  then "crítico"
    else                        "negativo"
    end
  end

  # ── OCIOSIDADE ────────────────────────────────────────────────────────────────

  def calc_idle_loss(base, ticket_medio)
    daily_counts = base
      .where(scheduled_at: 90.days.ago..Time.current)
      .group(Arel.sql("DATE(scheduled_at)"))
      .count

    return nil if daily_counts.empty?

    sorted_counts = daily_counts.values.sort
    p75_index     = [(sorted_counts.size * 0.75).ceil - 1, 0].max
    teto_realista = sorted_counts[p75_index].to_i
    # Atendimentos/dia é evento discreto — inteiro, arredondado pra cima.
    media_diaria  = (daily_counts.values.sum.to_f / daily_counts.size).ceil

    day_names   = %w[Domingo Segunda Terça Quarta Quinta Sexta Sábado]
    real_by_dow = base
      .where(scheduled_at: 90.days.ago..Time.current)
      .group(Arel.sql("EXTRACT(DOW FROM scheduled_at)::int"))
      .count

    idle_analysis = real_by_dow.map do |dow, total|
      semanas          = 90.0 / 7
      media_dow_float  = total.to_f / semanas
      media_dow        = media_dow_float.ceil
      gap              = [teto_realista - media_dow, 0].max
      # Receita usa o delta fracionário real — quem perde 2,4 atendimentos perde o
      # valor proporcional, mesmo que a contagem seja exibida como inteiro.
      gap_para_receita = [teto_realista - media_dow_float, 0].max
      {
        dia:                    day_names[dow],
        media_atendimentos:     media_dow,
        teto_realista:          teto_realista,
        gap_vs_teto:            gap,
        receita_perdida_semana: (gap_para_receita * ticket_medio).round(2)
      }
    end

    total_lost_mensal = (idle_analysis.sum { |d| d[:receita_perdida_semana] } * 4.3).round(2)
    worst_day         = idle_analysis.max_by { |d| d[:receita_perdida_semana] }
    best_day          = idle_analysis.max_by { |d| d[:media_atendimentos] }

    {
      analise_por_dia:        idle_analysis,
      media_diaria_real:      media_diaria,
      teto_realista_dia:      teto_realista,
      receita_perdida_mensal: total_lost_mensal,
      dia_mais_ocioso:        worst_day&.dig(:dia),
      dia_mais_cheio:         best_day&.dig(:dia),
      nota_metodologia:       "Estimativa baseada no percentil 75 dos dias reais do negócio nos últimos 90 dias.",
      ticket_base:            ticket_medio
    }
  end

  # ── PRECIFICAÇÃO DINÂMICA ─────────────────────────────────────────────────────

  def calc_dynamic_pricing(base, ticket_medio)
    return nil if ticket_medio.zero?

    hourly = base
      .where(scheduled_at: 90.days.ago..Time.current)
      .group(Arel.sql("EXTRACT(HOUR FROM scheduled_at)::int"))
      .count

    by_dow = base
      .where(scheduled_at: 90.days.ago..Time.current)
      .group(Arel.sql("EXTRACT(DOW FROM scheduled_at)::int"))
      .count

    return nil if hourly.empty? || by_dow.empty?

    avg_hourly = hourly.values.sum.to_f / hourly.size
    avg_dow    = by_dow.values.sum.to_f / by_dow.size
    day_names  = %w[Domingo Segunda Terça Quarta Quinta Sexta Sábado]

    dias_ociosos = by_dow.select { |_, c| c < avg_dow * 0.60 }
      .map { |dow, c| { dia: day_names[dow], atendimentos_90d: c } }

    dias_pico = by_dow.select { |_, c| c > avg_dow * 1.40 }
      .map { |dow, c| { dia: day_names[dow], atendimentos_90d: c } }

    horas_ociosas = hourly.select { |_, c| c < avg_hourly * 0.50 }.sort_by { |_, c| c }
      .map { |h, c| { hora: "#{h}h", atendimentos_90d: c } }

    horas_pico = hourly.select { |_, c| c > avg_hourly * 1.50 }.sort_by { |_, c| -c }
      .map { |h, c| { hora: "#{h}h", atendimentos_90d: c } }

    impacto_desconto = if dias_ociosos.any?
      semanas                  = (90.0 / 7).round(1)
      volume_semanal_ociosos   = dias_ociosos.sum { |d| d[:atendimentos_90d].to_f / semanas }
      aumento_estimado         = volume_semanal_ociosos * 0.35
      receita_adicional_mensal = (aumento_estimado * ticket_medio * 0.80 * 4.3).round(2)
      { dias: dias_ociosos.map { |d| d[:dia] }, desconto_sugerido: "15–20%",
        aumento_volume_estimado: "30–40%", receita_adicional_mensal: receita_adicional_mensal,
        nota: "Estimativa baseada em elasticidade típica do setor." }
    end

    impacto_aumento = if dias_pico.any?
      semanas                  = (90.0 / 7).round(1)
      volume_semanal_pico      = dias_pico.sum { |d| d[:atendimentos_90d].to_f / semanas }
      receita_adicional_mensal = (volume_semanal_pico * ticket_medio * 0.08 * 4.3).round(2)
      { dias: dias_pico.map { |d| d[:dia] }, aumento_sugerido: "7–10%",
        queda_volume_estimada: "< 5%", receita_adicional_mensal: receita_adicional_mensal,
        nota: "Em dias de alta demanda, cliente com carro parado tem baixa elasticidade a preço." }
    end

    {
      horas_ociosas:    horas_ociosas,
      horas_pico:       horas_pico,
      dias_ociosos:     dias_ociosos,
      dias_pico:        dias_pico,
      impacto_desconto: impacto_desconto,
      impacto_aumento:  impacto_aumento
    }
  end

  # ── FUNIL DE CONVERSÃO ────────────────────────────────────────────────────────

  def fetch_conversion_funnel
    all_services = car_wash.services.pluck(:title, :price).to_h
    return nil if all_services.empty?

    avg_price         = all_services.values.sum.to_f / all_services.size
    entry_threshold   = avg_price * 0.5
    premium_threshold = avg_price * 1.2

    entry_titles   = all_services.select { |_, p| p.to_f <= entry_threshold }.keys
    premium_titles = all_services.select { |_, p| p.to_f >= premium_threshold }.keys

    return nil if entry_titles.empty? || premium_titles.empty?

    first_visit_subquery = car_wash.appointments
      .where(status: "attended")
      .select("user_id, MIN(scheduled_at) AS first_at")
      .group(:user_id)

    first_visits = car_wash.appointments
      .where(status: "attended")
      .joins(:service)
      .joins(
        "INNER JOIN (#{first_visit_subquery.to_sql}) fv
         ON appointments.user_id = fv.user_id
         AND appointments.scheduled_at = fv.first_at"
      )
      .pluck(:user_id, "services.title", "appointments.scheduled_at")

    starters_by_service = {}
    first_date_by_user  = {}

    first_visits.each do |user_id, svc_title, first_date|
      next unless entry_titles.include?(svc_title)
      starters_by_service[svc_title] ||= []
      starters_by_service[svc_title] << user_id
      first_date_by_user[user_id] = first_date
    end

    return nil if starters_by_service.empty?

    all_starter_ids = starters_by_service.values.flatten.uniq

    premium_appts = car_wash.appointments
      .where(status: "attended", user_id: all_starter_ids)
      .joins(:service)
      .where(services: { title: premium_titles })
      .pluck(:user_id, "services.title", "services.price", "appointments.scheduled_at")

    premium_by_user = premium_appts.group_by { |row| row[0] }

    avg_premium_ticket = if premium_appts.any?
      premium_appts.map { |row| row[2].to_f }.sum / premium_appts.size
    else
      premium_titles.map { |t| all_services[t].to_f }.sum / [premium_titles.size, 1].max
    end

    funnel = {}

    starters_by_service.each do |entry_service, user_ids|
      total_starters  = user_ids.size
      converted       = user_ids.select { |uid| premium_by_user.key?(uid) }
      converted_count = converted.size
      conversion_rate = (converted_count.to_f / total_starters * 100).round(1)

      conversion_times = converted.map do |uid|
        first_premium = premium_by_user[uid].map { |r| r[3] }.min
        first_entry   = first_date_by_user[uid]
        next nil unless first_premium && first_entry
        ((first_premium - first_entry) / 1.day).round
      end.compact

      avg_days_to_convert = conversion_times.any? ? (conversion_times.sum.to_f / conversion_times.size).round : nil

      premium_revenue_from_starters = converted.sum do |uid|
        premium_by_user[uid].sum { |r| r[2].to_f }
      end.round(2)

      loss_per_lost_entry_client = (conversion_rate / 100.0 * avg_premium_ticket).round(2)

      funnel[entry_service] = {
        preco_entrada:                    all_services[entry_service].to_f,
        clientes_iniciaram_aqui:          total_starters,
        converteram_para_premium:         converted_count,
        taxa_conversao_pct:               conversion_rate,
        dias_medio_ate_conversao:         avg_days_to_convert,
        receita_premium_gerada:           premium_revenue_from_starters,
        perda_futura_por_cliente_perdido: loss_per_lost_entry_client,
        avg_premium_ticket_referencia:    avg_premium_ticket.round(2)
      }
    end

    {
      servicos_entrada:     entry_titles,
      servicos_premium:     premium_titles,
      limiar_entrada_preco: entry_threshold.round(2),
      limiar_premium_preco: premium_threshold.round(2),
      funil:                funnel
    }
  rescue => e
    Rails.logger.warn("Conversion funnel error: #{e.message}")
    nil
  end

  # ── PIPELINE LOSS 60D ─────────────────────────────────────────────────────────

  def calc_pipeline_loss(funnel_context, services_perf)
    return nil unless funnel_context&.dig(:funil)&.any?

    total_pipeline_loss = 0
    detalhes = []

    funnel_context[:funil].each do |entry_service, dados|
      svc_data = services_perf.find { |s| s[:servico] == entry_service }
      next unless svc_data

      last_m = svc_data[:atendimentos_ultimo_mes].to_i
      prev_m = svc_data[:atendimentos_mes_anterior].to_i
      next if prev_m.zero? || last_m >= prev_m

      queda_absoluta    = prev_m - last_m
      perda_por_cliente = dados[:perda_futura_por_cliente_perdido].to_f
      perda_projetada   = (queda_absoluta * perda_por_cliente).round(2)
      total_pipeline_loss += perda_projetada
      dias_ate_impacto  = dados[:dias_medio_ate_conversao] || 60

      detalhes << {
        servico_entrada:    entry_service,
        queda_clientes:     queda_absoluta,
        taxa_conversao_pct: dados[:taxa_conversao_pct],
        ticket_premium:     dados[:avg_premium_ticket_referencia].to_f,
        perda_projetada:    perda_projetada,
        impacto_em_dias:    dias_ate_impacto,
        mensagem: "Queda de #{queda_absoluta} cliente(s) em #{entry_service} representa " \
                  "R$ #{perda_projetada} em receita premium não gerada nos próximos #{dias_ate_impacto} dias."
      }
    end

    return nil if detalhes.empty?

    {
      perda_pipeline_total_60d: total_pipeline_loss.round(2),
      detalhes:                 detalhes,
      nota: "Projeção baseada em dados reais de conversão. Representa receita premium " \
            "que deixará de entrar nos próximos 60–90 dias se a queda nos serviços de entrada não for revertida."
    }
  rescue => e
    Rails.logger.warn("Pipeline loss error: #{e.message}")
    nil
  end

  # ── MESMO PERÍODO ANO ANTERIOR ────────────────────────────────────────────────

  def same_period_last_year(base)
    last_year_start = Date.current.beginning_of_month << 12
    last_year_end   = last_year_start.end_of_month

    revenue_ly = base.where(scheduled_at: last_year_start..last_year_end).sum("services.price").to_f
    count_ly   = base.where(scheduled_at: last_year_start..last_year_end).count
    return nil if count_ly.zero?

    { mes_referencia: last_year_start.strftime("%b/%Y"), faturamento: revenue_ly.round(2),
      agendamentos: count_ly, ticket_medio: count_ly > 0 ? (revenue_ly / count_ly).round(2) : 0 }
  end

  # ── PADRÃO DE ABANDONO ────────────────────────────────────────────────────────

  def detect_abandonment_pattern
    all_appts       = car_wash.appointments.where(status: "attended").joins(:user)
    visits_per_user = all_appts.group(:user_id).count
    single_users    = visits_per_user.select { |_, c| c == 1 }.keys
    return nil if single_users.empty?

    first_dates = all_appts.where(user_id: single_users).group(:user_id).minimum(:scheduled_at)
    by_month    = first_dates
      .group_by { |_, d| d.strftime("%Y-%m") }
      .map { |m, e| { mes: m, clientes_unica_visita: e.count } }
      .sort_by { |e| e[:mes] }.last(6)

    peak = by_month.max_by { |e| e[:clientes_unica_visita] }
    { abandono_por_mes: by_month, mes_maior_abandono: peak&.dig(:mes), pico_abandono: peak&.dig(:clientes_unica_visita) }
  rescue => e
    Rails.logger.warn("Abandonment pattern error: #{e.message}"); nil
  end

  # ── CONTEXTO PRINCIPAL ────────────────────────────────────────────────────────

  def build_context
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
        last_m   = base.where(services: { title: s.title }, scheduled_at: 30.days.ago..Time.current).count
        prev_m   = base.where(services: { title: s.title }, scheduled_at: 60.days.ago..30.days.ago).count
        variacao = prev_m > 0 ? (((last_m.to_f / prev_m) - 1) * 100).round(1) : nil
        { servico: s.title, total_atendimentos: s.total_count.to_i,
          receita_total: s.total_revenue.to_f.round(2),
          valor_por_atendimento: s.total_count > 0 ? (s.total_revenue.to_f / s.total_count).round(2) : 0,
          atendimentos_ultimo_mes: last_m, atendimentos_mes_anterior: prev_m,
          variacao_volume: variacao ? "#{variacao}%" : "sem dados" }
      end

    price_changes = base.group("services.title")
      .pluck("services.title, MIN(services.price), MAX(services.price)")
      .map { |t, mn, mx| { servico: t, preco_minimo: mn.to_f, preco_maximo: mx.to_f, houve_aumento: mx.to_f > mn.to_f } }

    client_counts     = base.group(:user_id).count
    recurring_clients = client_counts.count { |_, c| c > 1 }
    new_clients_count = client_counts.count { |_, c| c == 1 }
    total_clients     = client_counts.size
    retention_rate    = total_clients > 0 ? ((recurring_clients.to_f / total_clients) * 100).round(1) : 0
    # Visitas são eventos discretos — sempre inteiro. Arredonda pra cima.
    avg_visits        = recurring_clients > 0 ? (client_counts.select { |_, c| c > 1 }.values.sum.to_f / recurring_clients).ceil : 0

    all_last_visit = car_wash.appointments.where(status: "attended")
      .joins(:user).group(:user_id).maximum(:scheduled_at)

    # Análise estrutural: só agregados, nunca identificação individual.
    at_risk_entries = all_last_visit.select { |_, last| last < 30.days.ago && last > 90.days.ago }
    at_risk_count   = at_risk_entries.size
    at_risk_user_ids = at_risk_entries.keys

    at_risk_media_dias = if at_risk_count > 0
      somados = at_risk_entries.values.sum { |d| (Time.current - d).to_f / 1.day }
      (somados / at_risk_count).ceil
    else
      0
    end

    at_risk_receita_historica = if at_risk_count > 0
      base.where(user_id: at_risk_user_ids).sum("services.price").to_f.round(2)
    else
      0.0
    end

    pct_base_em_risco = total_clients > 0 ? ((at_risk_count.to_f / total_clients) * 100).round(1) : 0.0

    lost_clients = all_last_visit.count { |_, last| last < 90.days.ago }

    first_visits_data = car_wash.appointments.where(status: "attended")
      .joins(:user).group("users.id").minimum(:scheduled_at)

    new_by_month = first_visits_data
      .group_by { |_, d| d.strftime("%Y-%m") }
      .map { |month, entries| { mes: month, novos_clientes: entries.count } }
      .sort_by { |e| e[:mes] }.last(6)

    prev_month_new = first_visits_data.count { |_, d| d >= 60.days.ago && d < 30.days.ago }
    this_month_new = first_visits_data.count { |_, d| d >= 30.days.ago }
    growth_rate    = prev_month_new > 0 ? (((this_month_new.to_f / prev_month_new) - 1) * 100).round(1) : nil

    total_past    = car_wash.appointments.where("scheduled_at < ?", Time.current).where.not(status: "cancelled").count
    total_no_show = car_wash.appointments.where(status: "no_show").count
    no_show_rate  = total_past > 0 ? ((total_no_show.to_f / total_past) * 100).round(1) : 0

    dias_restantes_no_mes  = Date.current.end_of_month.day - Date.current.day
    faturamento_mes_atual  = base
      .where(scheduled_at: Time.current.beginning_of_month..Time.current)
      .sum("services.price").to_f.round(2)
    melhor_mes_historico   = monthly.map { |m| m[:faturamento] }.max.to_f
    meta_excelencia        = melhor_mes_historico > 0 ? melhor_mes_historico : nil
    meta_excelencia_diaria = (meta_excelencia && dias_restantes_no_mes > 0) ?
      ((meta_excelencia - faturamento_mes_atual) / dias_restantes_no_mes).round(2) : nil

    funil_conversao   = fetch_conversion_funnel
    pipeline_loss_60d = calc_pipeline_loss(funil_conversao, services_perf)

    {
      data_atual:                       Time.current.strftime("%d/%m/%Y"),
      dia_do_mes_atual:                 Date.current.day,
      dias_restantes_no_mes:            dias_restantes_no_mes,
      faturamento_mes_atual:            faturamento_mes_atual,
      meta_excelencia_historica:        meta_excelencia&.round(2),
      meta_excelencia_por_dia_restante: meta_excelencia_diaria,
      tipo_de_ciclo:                    cycle_type,
      mes_atual:                        Time.current.strftime("%B de %Y"),
      nome:                             car_wash.name,
      localizacao:                      car_wash.location_context.presence || "não informada",
      bairro:                           car_wash.bairro,
      cidade:                           car_wash.cidade,
      uf:                               car_wash.uf,
      clima_ultimos_30_dias:            fetch_climate(car_wash.latitude, car_wash.longitude),
      feriados_proximos_15_dias:        upcoming_holidays,
      saude_financeira:                 fetch_margin_context,
      ociosidade:                       calc_idle_loss(base, ticket_medio),
      precificacao_dinamica:            calc_dynamic_pricing(base, ticket_medio),
      funil_conversao:                  funil_conversao,
      pipeline_loss_60d:                pipeline_loss_60d,
      mesmo_periodo_ano_anterior:       same_period_last_year(base),
      padrao_abandono:                  detect_abandonment_pattern,
      faturamento_total:                total_sales.round(2),
      faturamento_ultimos_30_dias:      last_30_revenue.round(2),
      faturamento_30_60_dias:           prev_30_revenue.round(2),
      variacao_faturamento_mensal:      revenue_growth ? "#{revenue_growth}%" : "sem dados",
      atendimentos_30_dias:             last_30_count,
      atendimentos_30_60_dias:          prev_30_count,
      valor_medio_por_atendimento:      ticket_medio,
      historico_6_meses:                monthly,
      taxa_no_show:                     "#{no_show_rate}%",
      agendamentos_confirmados_proximos_30_dias: upcoming_confirmed,
      receita_projetada_proximos_7_dias:         upcoming_7d.round(2),
      variacao_precos_por_servico:      price_changes,
      percentual_clientes_que_voltam:   "#{retention_rate}%",
      media_visitas_cliente_fiel:       avg_visits,
      total_clientes:                   total_clients,
      clientes_que_voltaram:            recurring_clients,
      clientes_que_vieram_so_uma_vez:   new_clients_count,
      melhor_dia:                       best_day,
      pior_dia:                         worst_day,
      horarios_mais_movimentados:       peak_hours,
      horarios_ociosos:                 idle_hours,
      movimento_por_dia_da_semana:      demand_by_dow,
      servicos:                         services_perf,
      clientes_em_risco_30_a_90d: {
        quantidade:                     at_risk_count,
        pct_da_base_total:              pct_base_em_risco,
        media_dias_sem_visita:          at_risk_media_dias,
        receita_historica_representada: at_risk_receita_historica,
        ticket_medio_historico_grupo:   at_risk_count > 0 ? (at_risk_receita_historica / at_risk_count).round(2) : 0.0
      },
      clientes_perdidos_mais_90_dias:   lost_clients,
      novos_clientes_este_mes:          this_month_new,
      novos_clientes_mes_anterior:      prev_month_new,
      variacao_novos_clientes:          growth_rate ? "#{growth_rate}%" : "sem dados",
      novos_clientes_por_mes:           new_by_month
    }
  end

  # ── PROMPT ────────────────────────────────────────────────────────────────────

  def build_prompt(ctx, owner_input = nil, previous_inputs = [], previous_action = nil)
    tipo = ctx[:tipo_de_ciclo]
    sf   = ctx[:saude_financeira]
    is_critical = sf&.dig(:is_critical_state) || false

    cycle_instruction = if tipo == "fechamento"
      <<~CYCLE
        ═══ TIPO DE CICLO: FECHAMENTO DO MÊS ANTERIOR ══════════════════════
        Hoje é dia #{ctx[:dia_do_mes_atual]}. Este é o ciclo de FECHAMENTO.
        FOCO: avaliar o mês que terminou com números finais — não parciais.
        Compare com o mesmo mês do ano anterior e com o mês imediatamente anterior.
        A decisao_prioritaria deve atacar o maior problema estrutural identificado.
      CYCLE
    else
      <<~CYCLE
        ═══ TIPO DE CICLO: ACOMPANHAMENTO DO MÊS EM CURSO ══════════════════
        Hoje é dia #{ctx[:dia_do_mes_atual]}. Este é o ciclo de ACOMPANHAMENTO.
        FOCO: o mês está pela metade — dados são PARCIAIS.
        Projete o mês completo multiplicando o ritmo atual pelos dias restantes.
        Não compare total parcial com total completo sem avisar.
        A decisao_prioritaria deve ser a maior alavanca financeira disponível.
      CYCLE
    end

    crisis_instruction = if is_critical
      prejuizo    = sf[:lucro_atual].abs
      faturamento = sf[:media_faturamento_3m]
      aluguel     = sf[:aluguel_atual]
      salarios    = sf[:salarios_atual]

      aluguel_alerta = sf[:alertas_custo]&.find { |a| a[:linha] == "aluguel" }
      aluguel_linha  = if aluguel_alerta
        "Aluguel em #{aluguel_alerta[:pct_atual]}% da receita — +#{aluguel_alerta[:delta_pp]}pp acima da média dos últimos #{aluguel_alerta[:meses_de_historico]} meses fechados (#{aluguel_alerta[:pct_media_historica]}%). Voltar à média histórica representa R$ #{aluguel_alerta[:impacto_mensal_se_voltar_a_media]}/mês."
      elsif !sf[:referencia_suficiente]
        "Aluguel R$ #{aluguel}/mês — histórico insuficiente pra comparação. Avalie diretamente o contrato vs faturamento atual."
      else
        "Aluguel R$ #{aluguel}/mês está em linha com o próprio histórico do negócio. Em crise, renegociação direta continua sendo alavanca possível — mas o problema maior pode estar em outro lugar."
      end

      <<~CRISIS
        ═══ MODO DE CRISE ATIVADO ═══════════════════════════════════════════
        Prejuízo de R$ #{prejuizo} com faturamento médio de R$ #{faturamento}/mês.
        Custos fixos dominantes: aluguel R$ #{aluguel}/mês + salários R$ #{salarios}/mês.
        #{aluguel_linha}

        REGRAS OBRIGATÓRIAS:
        1. 80% da análise deve focar em corte de custos fixos e estancamento de caixa.
        2. Funil, retenção e crescimento são SECUNDÁRIOS — mencione brevemente e use
           a frase: "otimizar [métrica] agora é arrumar a decoração enquanto a casa pega fogo."
        3. A decisao_prioritaria DEVE ser sobre custo estrutural ou geração de caixa imediato.
        4. Ao quantificar impacto de corte, use EXCLUSIVAMENTE a referência do próprio
           histórico do negócio (campos alertas_custo[*].pct_media_historica e delta_pp).
           NÃO invente "aluguel ideal é X%" ou "benchmark de setor é Y%" — não temos
           estudo vetado pra lava-rápido no Brasil. Se o campo referencia_suficiente for
           false, diga claramente que não há base comparativa ainda.
        5. Nunca sugira marketing, funil ou precificação como decisão principal em crise.
        6. Tom: interventor cirúrgico, não consultor motivacional.
      CRISIS
    else
      ""
    end

    custos_suspeitos_instrucao = if sf&.dig(:custos_suspeitos)
      media_hist = sf[:media_custos_fixos_historica]
      atual      = sf[:custos_fixos_estimados]
      <<~WARN
        ⚠️ ALERTA DE DADOS INCOMPLETOS: os custos fixos deste mês (R$ #{atual}) estão abaixo
        de 60% da média histórica dos meses anteriores (R$ #{media_hist}). Isso indica que
        o lançamento de custos está incompleto — aluguel, salários ou outras linhas fixas
        provavelmente ainda não foram lançadas para este mês.
        OBRIGATÓRIO: na seção "sales", avise o dono que o break-even e a margem atual podem
        estar subestimados. Use a frase: "Os custos deste mês parecem incompletos — a margem
        pode cair quando você lançar o restante do aluguel e salários."
        Não omita esse aviso. Não suavize.
      WARN
    else
      ""
    end

    input_block = owner_input.present? ? <<~INPUT
      O DONO REPORTOU O SEGUINTE SOBRE O PERÍODO:
      #{owner_input}
      Cruze com os números. Se funcionou, confirme com dados. Se não funcionou, explique e mude. Não elogie — avalie.
    INPUT
    : "O dono não registrou nenhuma ação neste ciclo."

    history_block = previous_inputs.any? ? <<~HISTORY
      CICLOS ANTERIORES (não repita sugestões já dadas):
      #{previous_inputs.map.with_index { |inp, i| "Ciclo -#{i+1} (#{inp['saved_at']}): #{inp['text']}" }.join("\n")}
    HISTORY
    : ""

    validation_block = previous_action.present? ? <<~VALIDATION
      A DECISÃO SUGERIDA NO CICLO ANTERIOR FOI:
      "#{previous_action}"
      OBRIGATÓRIO: comece o "cycle_summary" avaliando se essa decisão teve impacto. Use números concretos. Nunca use "os números falam por si".
    VALIDATION
    : ""

    climate_instruction = if ctx[:clima_ultimos_30_dias]
      c = ctx[:clima_ultimos_30_dias]
      case c[:perfil_clima]
      when "muito_chuvoso"
        "ATENÇÃO CLIMA: #{c[:dias_de_chuva_ultimos_30_dias]} dias de chuva nos últimos 30 dias (#{c[:periodo]}, #{c[:total_chuva_mm]}mm). Período cruza dois meses — não atribua toda a chuva a um único mês."
      when "chuvoso"
        "CLIMA: #{c[:dias_de_chuva_ultimos_30_dias]} dias de chuva (#{c[:periodo]}, #{c[:total_chuva_mm]}mm)."
      else
        "CLIMA: favorável (#{c[:dias_de_chuva_ultimos_30_dias]} dias de chuva). Queda de movimento não tem justificativa climática."
      end
    else; ""; end

    holiday_instruction = if ctx[:feriados_proximos_15_dias]&.any?
      feriados = ctx[:feriados_proximos_15_dias].map { |h| "#{h[:nome]} (#{h[:dia]}, #{h[:data]}, em #{h[:dias_ate]} dias)" }.join(", ")
      "FERIADOS NOS PRÓXIMOS 15 DIAS: #{feriados}."
    else; ""; end

    meta_instrucao = if !is_critical && ctx[:dias_restantes_no_mes].to_i > 0 && ctx[:meta_excelencia_historica].to_f > 0
      falta = (ctx[:meta_excelencia_historica] - ctx[:faturamento_mes_atual]).round(2)
      if falta > 0
        "META DE EXCELÊNCIA: melhor mês histórico foi R$ #{ctx[:meta_excelencia_historica]}. Faltam R$ #{falta} em #{ctx[:dias_restantes_no_mes]} dias = R$ #{ctx[:meta_excelencia_por_dia_restante]}/dia."
      else
        "META DE EXCELÊNCIA SUPERADA: faturamento atual (R$ #{ctx[:faturamento_mes_atual]}) já superou o melhor mês histórico (R$ #{ctx[:meta_excelencia_historica]}). Mencione isso."
      end
    else; ""; end

    margin_instruction = if sf
      break_even_str = if sf[:break_even_atendimentos]
        faltam     = sf[:atendimentos_para_break_even].to_i
        realizados = sf[:atendimentos_realizados_mes].to_i

        base_str = faltam > 0 ?
          "BREAK-EVEN: #{sf[:break_even_atendimentos]} atendimentos para cobrir custos. Realizados: #{realizados}. Faltam #{faltam}." :
          "BREAK-EVEN SUPERADO: #{realizados} atendimentos. Cada atendimento adicional é lucro puro."

        sf[:break_even_pode_estar_subestimado] ?
          base_str + " ATENÇÃO: esse break-even pode estar subestimado — custos fixos deste mês parecem incompletos." :
          base_str
      else; ""; end

      alertas_str  = sf[:alertas_custo]&.any? ? sf[:alertas_custo].map { |a| a[:mensagem] }.join(" | ") : nil
      custo_ok_str = if sf[:custos_estaveis_vs_historico] && alertas_str.nil?
        "CUSTOS ESTÁVEIS VS. HISTÓRICO: estrutura de custos em linha com a média dos últimos #{sf[:referencia_meses]} meses fechados do próprio negócio. Sem desvio pontual, mas otimização estrutural continua valendo."
      elsif !sf[:referencia_suficiente]
        "REFERÊNCIA HISTÓRICA INDISPONÍVEL: ainda há menos de 3 meses fechados — não dá pra comparar com o próprio histórico. Evite afirmações sobre custo estar 'alto' ou 'baixo' sem base."
      elsif !sf[:referencia_mes_completo]
        "ALERTAS DE CUSTO SUSPENSOS: mês corrente ainda parcial (antes do dia 28) — % de custo sobre receita fica distorcido. Alertas vs histórico só rodam com mês fechado."
      else
        ""
      end

      case sf[:perfil_financeiro]
      when "saudável"
        "SAÚDE FINANCEIRA — SAUDÁVEL: margem #{sf[:margem_atual]}%, lucro R$ #{sf[:lucro_atual]}. #{break_even_str} #{custo_ok_str}#{alertas_str}"
      when "apertado"
        "SAÚDE FINANCEIRA — APERTADA: margem #{sf[:margem_atual]}%, lucro R$ #{sf[:lucro_atual]}. #{break_even_str} #{alertas_str || custo_ok_str}"
      when "crítico"
        "SAÚDE FINANCEIRA — CRÍTICA: margem #{sf[:margem_atual]}%, lucro R$ #{sf[:lucro_atual]}. #{break_even_str} #{alertas_str || custo_ok_str}"
      when "negativo"
        "SAÚDE FINANCEIRA — NEGATIVA: prejuízo de R$ #{sf[:lucro_atual].abs}. #{break_even_str} #{alertas_str || custo_ok_str}"
      else
        "SAÚDE FINANCEIRA: margem #{sf[:margem_atual]}%, lucro R$ #{sf[:lucro_atual]}. #{break_even_str}"
      end
    else
      "SAÚDE FINANCEIRA: custos não cadastrados. Encoraje o dono a cadastrar os custos mensais."
    end

    pricing_instruction = if !is_critical && ctx[:precificacao_dinamica]
      pd    = ctx[:precificacao_dinamica]
      parts = []
      if pd[:impacto_desconto]&.dig(:receita_adicional_mensal).to_f > 0
        parts << "DESCONTO em dias ociosos (#{pd[:impacto_desconto][:dias]&.join(', ')}): projeta +R$ #{pd[:impacto_desconto][:receita_adicional_mensal]}/mês."
      end
      if pd[:impacto_aumento]&.dig(:receita_adicional_mensal).to_f > 0
        parts << "AUMENTO em dias de pico (#{pd[:impacto_aumento][:dias]&.join(', ')}): projeta +R$ #{pd[:impacto_aumento][:receita_adicional_mensal]}/mês."
      end
      parts.any? ? "PRECIFICAÇÃO DINÂMICA: #{parts.join(' | ')}" : ""
    else; ""; end

    idle_instruction = if !is_critical && ctx[:ociosidade]&.dig(:receita_perdida_mensal).to_f > 0
      o = ctx[:ociosidade]
      "OCIOSIDADE: média real #{o[:media_diaria_real]} atendimentos/dia. Teto realista #{o[:teto_realista_dia]}/dia. Gap = R$ #{o[:receita_perdida_mensal]}/mês. Dia mais ocioso: #{o[:dia_mais_ocioso]}."
    else; ""; end

    funnel_instruction = if ctx[:funil_conversao] && !is_critical
      fc     = ctx[:funil_conversao]
      linhas = fc[:funil].map do |svc, d|
        "#{svc}: #{d[:clientes_iniciaram_aqui]} iniciaram, #{d[:taxa_conversao_pct]}% converteram para premium, " \
        "perda/cliente perdido: R$ #{d[:perda_futura_por_cliente_perdido]}, tempo médio: #{d[:dias_medio_ate_conversao] || 'n/d'} dias"
      end.join(" | ")
      "FUNIL DE CONVERSÃO: #{linhas}."
    elsif ctx[:funil_conversao] && is_critical
      "FUNIL: dados disponíveis mas secundários no modo de crise."
    else; ""; end

    pipeline_instruction = if ctx[:pipeline_loss_60d] && !is_critical
      pl       = ctx[:pipeline_loss_60d]
      detalhes = pl[:detalhes].map { |d| d[:mensagem] }.join(" | ")

      <<~PIPELINE
        PIPELINE LOSS: #{detalhes}
        TOTAL EM RISCO: R$ #{pl[:perda_pipeline_total_60d]} nos próximos 60–90 dias.
        Use esse número na seção "services" para mostrar o custo real da queda nos serviços de entrada.

        REGRA DE ALERTA ADJACENTE: se a decisao_prioritaria for outra alavanca, adicione ao final:
        "Atenção paralela: a queda em [serviço] hoje representa R$ [valor] em receita premium
        em risco para [mês estimado] — monitore e reverta antes do próximo ciclo."
        Aplicar quando pipeline_loss_60d > R$ 500.
      PIPELINE
    elsif ctx[:pipeline_loss_60d] && is_critical
      pl = ctx[:pipeline_loss_60d]
      "PIPELINE LOSS (secundário em crise): R$ #{pl[:perda_pipeline_total_60d]} em risco nos próximos 60 dias. Mencione brevemente."
    else; ""; end

    perfil_bairro = case ctx[:bairro].to_s.downcase
    when /paulista|jardins|itaim|moema|pinheiros|vila nova conceição|brooklin/
      "área nobre — cliente valoriza qualidade. Upselling e premiumização têm alta aceitação."
    when /centro|brás|bom retiro|pari|cambuci/
      "área comercial densa — agilidade, volume e preço competitivo."
    when /zona sul|campo limpo|capão redondo|m'boi mirim|grajaú/
      "área popular — preço acessível, volume e fidelização simples."
    else
      "analise o perfil da região e adapte ao poder aquisitivo local."
    end

    <<~PROMPT
      Você é um consultor financeiro especialista em lava-rápidos no Brasil. Direto, pé no chão, linguagem simples.
      Seu papel é identificar problemas estruturais e quantificar decisões — não dar receitas genéricas de vendas.

      #{cycle_instruction}
      #{crisis_instruction}

      ═══ ALERTAS DE DADOS ════════════════════════════════════════════════
      #{custos_suspeitos_instrucao}

      ═══ CONTEXTO FIXO ═══════════════════════════════════════════════════
      DATA DE HOJE: #{ctx[:data_atual]} (dia #{ctx[:dia_do_mes_atual]} do mês, #{ctx[:dias_restantes_no_mes]} dias restantes).

      IMPORTANTE: faturamento = EXCLUSIVAMENTE clientes que compareceram (attended). Agendamentos futuros são projeção separada.

      PROJEÇÃO FUTURA: #{ctx[:agendamentos_confirmados_proximos_30_dias]} agendamentos confirmados. R$ #{ctx[:receita_projetada_proximos_7_dias]} nos próximos 7 dias. No-show: #{ctx[:taxa_no_show]}.

      PRODUTO: app de agendamento. NUNCA sugira nada sobre agendamento ou marcação.
      CLIENTE FINAL: não faz nada. Nunca sugira pedir indicação, avaliação ou feedback, NEM que o dono entre em contato direto com cliente (WhatsApp, ligação, mensagem, e-mail, SMS). Ação 1:1 com cliente não faz parte do escopo.

      ═══ SINAIS DO PERÍODO ═══════════════════════════════════════════════
      #{climate_instruction}
      #{holiday_instruction}
      #{meta_instrucao}
      #{idle_instruction}

      ═══ SAÚDE FINANCEIRA ════════════════════════════════════════════════
      #{margin_instruction}

      ═══ PRECIFICAÇÃO DINÂMICA ═══════════════════════════════════════════
      #{pricing_instruction}

      ═══ FUNIL E PIPELINE ════════════════════════════════════════════════
      #{funnel_instruction}
      #{pipeline_instruction}

      ═══ PERFIL DO MERCADO ═══════════════════════════════════════════════
      REGIÃO (#{ctx[:bairro]}, #{ctx[:cidade]}): #{perfil_bairro}

      ═══ HIERARQUIA DE ANÁLISE ═══════════════════════════════════════════
      1. ESTRUTURAL: custos acima da própria média histórica (ver alertas_custo) | precificação abaixo do histórico de preço praticado | dados incompletos
      2. OPERACIONAL: ociosidade recorrente | no-show alto | ticket caindo | funil quebrado | pipeline loss alto
      3. TÁTICO: clientes em risco | feriado próximo | serviço premium sem exposição

      REGRA: decisao_prioritaria ataca o nível mais alto disponível.
      Em modo de crise: foco total em 1. Nunca pule para 3 ignorando 1 e 2.

      ═══ REGRAS DE ANÁLISE ═══════════════════════════════════════════════
      PREÇO: se já subiu, não sugira novo aumento — sugira premiumização por serviço específico.
      FUNIL: queda em serviço de entrada = pipeline_loss em R$ nos próximos 60–90 dias.
      DADOS INCOMPLETOS: se custos_suspeitos = true, avise antes de qualquer análise financeira.
      NÚMEROS: use dados reais do contexto. Nunca invente estimativas sem âncora nos dados.
      REFERÊNCIAS DE CUSTO — SEMPRE HISTÓRICO PRÓPRIO: a única referência vetada é o histórico do próprio negócio (campos alertas_custo, pct_media_historica, referencia_origem="historico_proprio_negocio"). NUNCA cite "benchmark do setor é X%", "aluguel ideal é Y%", "salários devem ficar entre A e B%". Essas referências NÃO existem no contexto porque não temos estudo vetado pra lava-rápido no Brasil. Se um alerta_custo está presente, use a mensagem pronta (compara com a própria média dos últimos N meses). Se referencia_suficiente=false, diga explicitamente que ainda não há histórico suficiente pra comparação.
      CLIENTES — ANONIMATO OBRIGATÓRIO: NUNCA cite nome, e-mail ou qualquer identificador de cliente individual. Sempre agregue: quantidade, % da base, receita histórica representada, média de dias sem visita. "10 clientes sumidos há ~45 dias representando R$ X em receita histórica" é correto. "Fulano, Ciclano, Beltrano estão há 40 dias sem aparecer" é ERRADO e não deve ocorrer em hipótese alguma.
      CONTATO 1:1 PROIBIDO: NUNCA sugira que o dono entre em contato com cliente (WhatsApp, ligação, mensagem, SMS, e-mail). Também NUNCA sugira pedir avaliação, indicação, feedback ou qualquer ação do cliente. A análise é estrutural — sistemas, processos, operação, preço, mix — não tática 1:1.
      VISITAS/ATENDIMENTOS — SEMPRE INTEIROS: visitas e atendimentos são eventos discretos. "3,6 visitas" não existe — é 4. Arredonde pra cima ao reportar qualquer contagem de visitas, atendimentos ou clientes.

      ═══ REGRAS DA DECISAO_PRIORITARIA ══════════════════════════════════
      1. Maior alavanca financeira disponível nos dados.
      2. Impacto em R$/mês usando dados reais.
      3. Custo: use delta vs média histórica do próprio negócio (alertas_custo[*].delta_pp e impacto_mensal_se_voltar_a_media). NUNCA cite benchmark externo que não está no contexto.
      4. Precificação: cite serviço pelo nome e valor atual.
      5. Funil: use pipeline_loss_60d do contexto.
      6. Retenção: quantifique em receita histórica em risco (R$) e % de churn agregado. NUNCA cite nomes. A recomendação é estrutural (cadência de pacotes, fidelidade, espaçamento médio entre visitas), nunca "entrar em contato com X".
      7. Nunca repita a decisão do ciclo anterior.
      8. Nunca use ações genéricas.
      9. Tomável hoje ou amanhã, sem investimento externo.
      10. Se pipeline_loss_60d > R$ 500 e a decisão for outra alavanca, adicione alerta
          adjacente ao final: "Atenção paralela: a queda em [serviço] representa R$ [X] em
          receita premium em risco para [mês estimado] — monitore antes do próximo ciclo."
      11. Varie a cada ciclo: custo → precificação → mix/funil → retenção → operacional.

      ═══ REGRAS DE ESCRITA ═══════════════════════════════════════════════
      1. Linguagem de conversa, sem termos técnicos.
      2. Comece pelo que melhorou (mesmo em crise, se houver algo).
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
        "sales":     { "text": "faturamento real, comparativo, projeção, break-even com ressalva de custos incompletos se aplicável", "status": "up|down|stable" },
        "services":  { "text": "serviços com evolução e pipeline_loss em R$ se disponível", "status": "up|down|stable" },
        "clients":   { "text": "retenção, visita única e abandono com nomes reais", "status": "up|down|stable" },
        "demand":    { "text": "distribuição real de demanda, ociosidade com valor real, precificação dinâmica por serviço específico", "status": "up|down|stable" },
        "retention": { "text": "retenção agregada: quantidade e % da base em risco, receita histórica representada, média de dias sem visita. NUNCA nomes. Recomendações estruturais (fidelidade, pacote, cadência), nunca contato 1:1.", "status": "up|down|stable" },
        "growth":    { "text": "novos clientes, feriados próximos e perfil do público captado", "status": "up|down|stable" },
        "cycle_summary": "avalia decisão anterior com dados. Resume o momento financeiro em 2 frases com meta concreta para os dias restantes.",
        "decisao_prioritaria": "maior alavanca financeira com problema, impacto em R$/mês e como executar. Se pipeline_loss > R$ 500, inclui alerta adjacente ao final. Estrutural > Operacional > Tático."
      }
    PROMPT
  end

  # ── PARSE / CALL ──────────────────────────────────────────────────────────────

  def parse_sections(raw)
    clean  = raw.to_s.gsub(/```json|```/, "").strip
    parsed = JSON.parse(clean)
    { ok: true, sections: parsed, error: nil }
  rescue => e
    Rails.logger.error("AiInsights parse error: #{e.message} — raw: #{raw.to_s[0..200]}")
    fallback = { "text" => raw.to_s, "status" => "stable" }
    sections = {
      "sales" => fallback, "services" => fallback, "clients" => fallback,
      "demand" => fallback, "retention" => fallback, "growth" => fallback,
      "cycle_summary" => "", "decisao_prioritaria" => ""
    }
    { ok: false, sections: sections, error: "#{e.class}: #{e.message}" }
  end

  # Retorna: { raw:, input_tokens:, output_tokens:, latency_ms:, error: }
  # Nunca levanta — caller decide como registrar a falha.
  def call_claude(prompt)
    uri  = URI("https://api.anthropic.com/v1/messages")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true; http.read_timeout = 120

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"]      = "application/json"
    request["x-api-key"]         = ENV["ANTHROPIC_API_KEY"]
    request["anthropic-version"] = "2023-06-01"

    request.body = {
      model:      MODEL,
      max_tokens: 6000,
      system:     "Você é um consultor financeiro especialista em lava-rápidos no Brasil. Direto, simples, sem termos técnicos. Nunca sugere nada sobre agendamento. Nunca pede nada ao cliente final NEM sugere que o dono entre em contato com cliente individual (WhatsApp, ligação, mensagem, e-mail, SMS). NUNCA cita nome, e-mail ou identificador de cliente — sempre agregados (quantidade, %, receita representada). Visitas e atendimentos são SEMPRE inteiros, arredondados pra cima — 3,6 visitas não existe. Análise é estrutural (custo, preço, mix, processo), nunca tática 1:1. NUNCA cita benchmark de setor (ex.: 'aluguel ideal 18%', 'salários 25–35%', 'produtos 8–14%') — não temos estudo vetado pra lava-rápido no Brasil. A única referência válida é o histórico do próprio negócio: quando o contexto trouxer alertas_custo, use a mensagem pronta (compara com pct_media_historica do próprio negócio). Se referencia_suficiente=false, diga que ainda não há base comparativa. Faturamento = apenas clientes que compareceram (attended). Hierarquia: estrutural > operacional > tático. Em modo de crise: 80% do foco em custo e caixa imediato. Se custos_suspeitos = true: avise sobre dados incompletos antes de qualquer análise financeira. Pipeline loss > R$ 500: inclui alerta adjacente ao final da decisao_prioritaria. Nunca inventa estimativas sem âncora nos dados. Capacidade ociosa = percentil 75 dos dias reais. Nunca usa 'os números falam por si'. Responde SEMPRE em JSON válido exatamente no formato solicitado.",
      messages:   [{ role: "user", content: prompt }]
    }.to_json

    started  = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = http.request(request)
    elapsed  = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    body = JSON.parse(response.body) rescue nil
    unless body
      return { raw: nil, input_tokens: nil, output_tokens: nil, latency_ms: elapsed,
               error: "Resposta inválida da API (HTTP #{response.code})" }
    end

    if body["error"]
      return { raw: nil, input_tokens: nil, output_tokens: nil, latency_ms: elapsed,
               error: "API error: #{body['error']['message'] || body['error']}" }
    end

    {
      raw:           body.dig("content", 0, "text") || "{}",
      input_tokens:  body.dig("usage", "input_tokens"),
      output_tokens: body.dig("usage", "output_tokens"),
      latency_ms:    elapsed,
      error:         nil,
    }
  rescue => e
    { raw: nil, input_tokens: nil, output_tokens: nil, latency_ms: nil,
      error: "#{e.class}: #{e.message}" }
  end
end
