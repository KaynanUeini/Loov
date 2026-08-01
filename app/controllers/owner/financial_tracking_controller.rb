module Owner
  class FinancialTrackingController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    # Atendente também acessa pra ver/lançar custos (a UI mostra só as
    # linhas de custo pra ele, esconde faturamento/lucro). Owner vê tudo.
    before_action :ensure_owner_or_attendant

    def index
      car_wash = current_user.linked_car_wash
      if car_wash.nil?
        redirect_to root_path, alert: "Você não tem um lava-rápido associado."
        return
      end

      @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : Date.current.beginning_of_month
      @end_date   = params[:end_date].present?   ? Date.parse(params[:end_date])   : Date.current.end_of_month

      if params[:period].present?
        case params[:period]
        when "day"
          @start_date  = Date.current
          @end_date    = Date.current
          @granularity = "hour"
        when "week"
          @start_date  = Date.current.beginning_of_week(:monday)
          @end_date    = Date.current.end_of_week(:monday)
          @granularity = "day"
        when "month"
          @start_date  = Date.current.beginning_of_month
          @end_date    = Date.current.end_of_month
          @granularity = "day"
        when "year"
          @start_date  = Date.current.beginning_of_year
          @end_date    = Date.current.end_of_year
          @granularity = "month"
        when "all"
          @start_date  = Date.new(2025, 1, 1)
          @end_date    = Date.current.end_of_year
          @granularity = "year"
        when "custom"
          @start_date  = params[:start_date].present? ? Date.parse(params[:start_date]) : Date.current.beginning_of_month
          @end_date    = params[:end_date].present?   ? Date.parse(params[:end_date])   : Date.current.end_of_month
          @granularity = "month"
        else
          @start_date  = Date.current.beginning_of_month
          @end_date    = Date.current.end_of_month
          @granularity = "day"
        end
      else
        @granularity = "day"
      end

      @is_year_filter   = params[:period] == "year"
      @is_all_filter    = params[:period] == "all"
      @is_custom_filter = params[:period] == "custom"

      # ── Curto-circuito JSON (app mobile) ───────────────────────────────────
      # Pula toda a computação só-HTML (top services, attendance, demand, etc)
      # quando o caller é o app — economiza 10+ queries por request.
      if request.format.json?
        return render json: build_financial_json(car_wash)
      end

      # ── BASE: apenas atendimentos efetivados pelo dono ─────────────────────
      base = car_wash.appointments
      .where(status: "attended")
      .where(scheduled_at: @start_date.beginning_of_day..@end_date.end_of_day)
      .joins(:service)

      base = base.where("services.title = ?", params[:service_filter]) if params[:service_filter].present?

      @appointments       = base
      @total_sales        = @appointments.sum("services.price - COALESCE(appointments.commission_amount, 0)").to_f
      @total_appointments = @appointments.count

      if @is_all_filter
        total_years    = (@end_date.year - @start_date.year) + 1
        @average_value = total_years.zero? ? 0.0 : (@total_sales / total_years).round(2)
        @average_label = "Média Anual"
      elsif @is_year_filter || @is_custom_filter
        total_months   = (@end_date.year * 12 + @end_date.month) - (@start_date.year * 12 + @start_date.month) + 1
        @average_value = total_months.zero? ? 0.0 : (@total_sales / total_months).round(2)
        @average_label = "Média Mensal"
      else
        total_days     = (@end_date - @start_date).to_i + 1
        @average_value = total_days.zero? ? 0.0 : (@total_sales / total_days).round(2)
        @average_label = "Média Diária"
      end

      # ── VENDAS POR DIA ─────────────────────────────────────────────────────
      sales_by_day_data = @appointments
      .group(Arel.sql("DATE(scheduled_at)"))
      .select("DATE(scheduled_at) AS sale_date, COUNT(*) AS appointment_count, SUM(services.price - COALESCE(appointments.commission_amount, 0)) AS total_value")
      .order(Arel.sql("DATE(scheduled_at) ASC"))

      @sales_by_day = (@start_date..@end_date).map do |date|
        entry = sales_by_day_data.find { |e| e.sale_date == date }
        OpenStruct.new(
          sale_date:         date,
          appointment_count: entry&.appointment_count || 0,
          total_value:       entry&.total_value.to_f
          )
      end

      # ── VENDAS POR MÊS ─────────────────────────────────────────────────────
      sales_by_month_data = @appointments
      .group(Arel.sql("DATE_TRUNC('month', scheduled_at)"))
      .select("DATE_TRUNC('month', scheduled_at) AS period_start, COUNT(*) AS appointment_count, SUM(services.price - COALESCE(appointments.commission_amount, 0)) AS total_value")
      .order(Arel.sql("period_start ASC"))

      all_months = []
      m = Date.new(@start_date.year, @start_date.month, 1)
      while m <= Date.new(@end_date.year, @end_date.month, 1)
        all_months << m
        m = m.next_month
      end

      @sales_by_month = all_months.map do |month|
        entry = sales_by_month_data.find { |e| e.period_start == month }
        OpenStruct.new(
          period_start:      month,
          appointment_count: entry&.appointment_count || 0,
          total_value:       entry&.total_value.to_f
          )
      end

      # ── VENDAS POR ANO ─────────────────────────────────────────────────────
      sales_by_year_data = @appointments
      .group(Arel.sql("DATE_TRUNC('year', scheduled_at)"))
      .select("DATE_TRUNC('year', scheduled_at) AS period_start, COUNT(*) AS appointment_count, SUM(services.price - COALESCE(appointments.commission_amount, 0)) AS total_value")
      .order(Arel.sql("period_start ASC"))

      @sales_by_year = (@start_date.year..@end_date.year).map do |year|
        y     = Date.new(year, 1, 1)
        entry = sales_by_year_data.find { |e| e.period_start == y }
        OpenStruct.new(
          period_start:      y,
          appointment_count: entry&.appointment_count || 0,
          total_value:       entry&.total_value.to_f
          )
      end

      # ── AGENDADOS CONFIRMADOS (projeção — linha laranja) ───────────────────
      confirmed_base = car_wash.appointments
      .where(status: "confirmed")
      .where(scheduled_at: @start_date.beginning_of_day..@end_date.end_of_day)
      .joins(:service)

      confirmed_base = confirmed_base.where("services.title = ?", params[:service_filter]) if params[:service_filter].present?

      # ── DADOS DO GRÁFICO ───────────────────────────────────────────────────
      case @granularity
      when "hour"
        sales_by_hour = @appointments
        .group(Arel.sql("DATE(scheduled_at - INTERVAL '3 hours'), EXTRACT(HOUR FROM (scheduled_at - INTERVAL '3 hours'))"))
        .select("DATE(scheduled_at - INTERVAL '3 hours'), EXTRACT(HOUR FROM (scheduled_at - INTERVAL '3 hours')) AS sale_hour, COUNT(*) AS appointment_count, SUM(services.price - COALESCE(appointments.commission_amount, 0)) AS total_value")
        .order(Arel.sql("DATE(scheduled_at - INTERVAL '3 hours') ASC, sale_hour ASC"))
        @chart_data = sales_by_hour.map { |e| { date: "#{e.sale_hour.to_i}:00", value: e.total_value.to_f } }

        confirmed_by_hour = confirmed_base
        .group(Arel.sql("DATE(scheduled_at - INTERVAL '3 hours'), EXTRACT(HOUR FROM (scheduled_at - INTERVAL '3 hours'))"))
        .select("DATE(scheduled_at - INTERVAL '3 hours'), EXTRACT(HOUR FROM (scheduled_at - INTERVAL '3 hours')) AS sale_hour, SUM(services.price - COALESCE(appointments.commission_amount, 0)) AS total_value")
        .order(Arel.sql("DATE(scheduled_at - INTERVAL '3 hours') ASC, sale_hour ASC"))
        confirmed_map = confirmed_by_hour.each_with_object({}) { |e, h| h["#{e.sale_hour.to_i}:00"] = e.total_value.to_f }
        @confirmed_chart_data = @chart_data.map { |d| { date: d[:date], value: confirmed_map[d[:date]] || 0 } }
      when "day"
        @chart_data = @sales_by_day.map { |e| { date: e.sale_date.strftime("%d/%m"), value: e.total_value.to_f } }

        confirmed_by_day = confirmed_base
        .group(Arel.sql("DATE(scheduled_at)"))
        .select("DATE(scheduled_at) AS sale_date, SUM(services.price - COALESCE(appointments.commission_amount, 0)) AS total_value")
        .order(Arel.sql("DATE(scheduled_at) ASC"))
        confirmed_map = confirmed_by_day.each_with_object({}) { |e, h| h[e.sale_date.strftime("%d/%m")] = e.total_value.to_f }
        @confirmed_chart_data = @chart_data.map { |d| { date: d[:date], value: confirmed_map[d[:date]] || 0 } }

      when "month"
        @chart_data = @sales_by_month.map { |e| { date: (I18n.l(e.period_start, format: "%b/%Y", locale: :"pt-BR") rescue e.period_start.strftime("%m/%Y")), value: e.total_value.to_f } }

        confirmed_by_month = confirmed_base
        .group(Arel.sql("DATE_TRUNC('month', scheduled_at)"))
        .select("DATE_TRUNC('month', scheduled_at) AS period_start, SUM(services.price - COALESCE(appointments.commission_amount, 0)) AS total_value")
        .order(Arel.sql("period_start ASC"))
        confirmed_map = confirmed_by_month.each_with_object({}) do |e, h|
          label = I18n.l(e.period_start.to_date, format: "%b/%Y", locale: :"pt-BR") rescue e.period_start.strftime("%m/%Y")
          h[label] = e.total_value.to_f
        end
        @confirmed_chart_data = @chart_data.map { |d| { date: d[:date], value: confirmed_map[d[:date]] || 0 } }

      when "year"
        @chart_data = @sales_by_year.map { |e| { date: e.period_start.strftime("%Y"), value: e.total_value.to_f } }

        confirmed_by_year = confirmed_base
        .group(Arel.sql("DATE_TRUNC('year', scheduled_at)"))
        .select("DATE_TRUNC('year', scheduled_at) AS period_start, SUM(services.price - COALESCE(appointments.commission_amount, 0)) AS total_value")
        .order(Arel.sql("period_start ASC"))
        confirmed_map = confirmed_by_year.each_with_object({}) { |e, h| h[e.period_start.strftime("%Y")] = e.total_value.to_f }
        @confirmed_chart_data = @chart_data.map { |d| { date: d[:date], value: confirmed_map[d[:date]] || 0 } }

      else
        @chart_data           = @sales_by_day.map { |e| { date: e.sale_date.strftime("%d/%m"), value: e.total_value.to_f } }
        @confirmed_chart_data = @chart_data.map { |d| { date: d[:date], value: 0 } }
      end

      # ── TRANSAÇÕES ─────────────────────────────────────────────────────────
      # left_outer_joins para não excluir walk-ins (sem user)
      transactions_query = car_wash.appointments
      .where(status: "attended")
      .where(scheduled_at: @start_date.beginning_of_day..@end_date.end_of_day)
      .joins(:service)
      .left_outer_joins(:user)
      .order("appointments.scheduled_at DESC")

      transactions_query = transactions_query.where("services.title = ?", params[:service_filter]) if params[:service_filter].present?

      @transactions = transactions_query.map do |a|
        client_name = if a.walk_in?
          a.walk_in_name.presence || "Avulso"
        else
          a.user&.email&.split("@")&.first&.capitalize || "—"
        end
        OpenStruct.new(
          scheduled_at:  a.scheduled_at,
          user_email:    client_name,
          service_title: a.service.title,
          service_price: a.respond_to?(:effective_price) ? a.effective_price : a.service.price
          )
      end

      # ── LISTA DE SERVIÇOS PARA FILTRO ──────────────────────────────────────
      @service_options = car_wash.services.pluck(:title).uniq.sort

      # ── DEMANDA POR DIA DA SEMANA ──────────────────────────────────────────
      @demand_by_dow = car_wash.appointments
      .where(status: "attended")
      .group(Arel.sql("EXTRACT(DOW FROM scheduled_at)::int"))
      .order(Arel.sql("EXTRACT(DOW FROM scheduled_at)::int"))
      .count
      .map { |dow, count| { dow: dow, count: count } }

      # ── HEATMAP POR DIA E HORA ─────────────────────────────────────────────
      heatmap_data = car_wash.appointments
      .where(status: "attended")
      .group(
        Arel.sql("EXTRACT(DOW FROM scheduled_at)::int"),
        Arel.sql("EXTRACT(HOUR FROM scheduled_at)::int")
        )
      .count
      @heatmap = heatmap_data.map { |(dow, hour), count| { dow: dow, hour: hour, count: count } }

      # ── SERVIÇOS: RECEITA VS VOLUME ────────────────────────────────────────
      @services_performance = car_wash.appointments
      .where(status: "attended")
      .joins(:service)
      .group("services.title")
      .select("services.title, COUNT(*) AS total_count, SUM(services.price - COALESCE(appointments.commission_amount, 0)) AS total_revenue")
      .order(Arel.sql("total_revenue DESC"))
      .map { |s| { title: s.title, count: s.total_count.to_i, revenue: s.total_revenue.to_f } }

      # ── CLIENTES RECORRENTES VS NOVOS ──────────────────────────────────────
      # Apenas clientes com user_id (exclui walk-ins anônimos)
      client_counts      = car_wash.appointments.where(status: "attended").where.not(user_id: nil).group(:user_id).count
      @recurring_clients = client_counts.count { |_, c| c > 1 }
      @new_clients       = client_counts.count { |_, c| c == 1 }
      @total_clients     = client_counts.size

      # ── TOP 5 CLIENTES ─────────────────────────────────────────────────────
      @top_clients = car_wash.appointments
      .where(status: "attended")
      .where.not(user_id: nil)
      .joins(:user)
      .group("users.email")
      .order(Arel.sql("count_all DESC"))
      .limit(5)
      .count
      .map { |email, count| { email: email.split("@").first.capitalize, count: count } }

      # ── RETENÇÃO — CLIENTES EM RISCO ──────────────────────────────────────
      all_client_last_visit = car_wash.appointments
      .where(status: "attended")
      .where.not(user_id: nil)
      .joins(:user)
      .group("users.email")
      .maximum(:scheduled_at)

      @at_risk_clients = all_client_last_visit
      .select { |_, last| last < 30.days.ago && last > 90.days.ago }
      .sort_by { |_, last| last }
      .first(10)
      .map { |email, last| { cliente: email.split("@").first.capitalize, ultima_visita: last.strftime("%d/%m/%Y"), dias_ausente: (Time.current - last).to_i / 1.day } }

      @lost_clients = all_client_last_visit.count { |_, last| last < 90.days.ago }

      # ── CRESCIMENTO DE BASE ────────────────────────────────────────────────
      first_visits = car_wash.appointments
      .where(status: "attended")
      .where.not(user_id: nil)
      .joins(:user)
      .group("users.id")
      .minimum(:scheduled_at)

      @new_clients_by_month = first_visits
      .group_by { |_, d| d.strftime("%Y-%m") }
      .map { |month, entries| { mes: month, novos_clientes: entries.count } }
      .sort_by { |e| e[:mes] }
      .last(6)

      @prev_month_new = first_visits.count { |_, d| d >= 60.days.ago && d < 30.days.ago }
      @this_month_new = first_visits.count { |_, d| d >= 30.days.ago }
      @growth_rate    = @prev_month_new > 0 ? (((@this_month_new.to_f / @prev_month_new) - 1) * 100).round(1) : nil

      # ── EXPORT CSV ────────────────────────────────────────────────────────
      if params[:format] == "csv"
        send_data generate_csv(@transactions),
        filename:    "transacoes_#{Date.current}.csv",
        type:        "text/csv"
        return
      end

      # ── TAXA DE COMPARECIMENTO (para app mobile) ───────────────────────────
      # Total de agendamentos no período excluindo apenas cancelados/rejeitados
      total_in_period = car_wash.appointments
        .where(scheduled_at: @start_date.beginning_of_day..@end_date.end_of_day)
        .where(status: %w[attended no_show confirmed])
        .count

      @attendance = {
        attended: @total_appointments,
        total:    total_in_period,
        rate:     total_in_period > 0 ? (@total_appointments.to_f / total_in_period * 100).round(1) : 0.0
      }

      # JSON já saiu acima via curto-circuito; aqui só HTML.
      respond_to do |format|
        format.html   # renderiza view erb normalmente
      end
    end

    private

    def ensure_owner_or_attendant
      unless current_user&.owner? || current_user&.attendant?
        if request.format.json?
          render json: { error: "Acesso negado." }, status: :forbidden
        else
          redirect_to root_path, alert: "Acesso restrito."
        end
      end
    end

    def generate_csv(transactions)
      require "csv"
      CSV.generate(headers: true) do |csv|
        csv << ["Data", "Horário", "Cliente", "Serviço", "Valor (R$)"]
        transactions.each do |t|
          csv << [
            t.scheduled_at.strftime("%d/%m/%Y"),
            t.scheduled_at.strftime("%H:%M"),
            t.user_email,
            t.service_title,
            format("%.2f", t.service_price.to_f)
          ]
        end
      end
    end

    # ── JSON shape v2 — otimizado: bulk-fetch + group_by SQL ───────────────
    # Roda numa quantidade pequena e constante de queries (≈5) independente
    # do tamanho do período. Antes era O(N) com N = dias no período.

    def build_financial_json(car_wash)
      cost_lookup       = build_cost_lookup(car_wash)
      revenue_in_period = revenue_sum_in_range(car_wash, @start_date, @end_date)
      open_revenue      = open_revenue_sum_in_range(car_wash, @start_date, @end_date)
      costs             = costs_for_range_fast(@start_date, @end_date, cost_lookup)
      profit            = revenue_in_period - costs[:total]
      margin            = revenue_in_period > 0 ? ((profit / revenue_in_period) * 100).round(1) : nil

      previous    = build_previous_comparison(car_wash, cost_lookup, revenue_in_period, profit)
      chart       = build_chart_series_fast(car_wash, @start_date, @end_date, @granularity, cost_lookup)
      monthly_dre = build_monthly_dre_fast(car_wash, cost_lookup)
      trailing    = build_trailing_12m(monthly_dre)

      {
        period:        params[:period] || "month",
        period_label:  build_period_label(@start_date, @end_date, params[:period]),
        start_date:    @start_date.iso8601,
        end_date:      @end_date.iso8601,
        granularity:   @granularity,
        kpis: {
          revenue:      revenue_in_period.round(2),
          open_revenue: open_revenue.round(2),
          costs:        costs,
          profit:       profit.round(2),
          margin:       margin
        },
        previous:      previous,
        chart:         chart,
        monthly_dre:   monthly_dre,
        trailing_12m:  trailing
      }
    end

    # Comparação com o período anterior. Um lucro sozinho não responde a
    # pergunta que o dono realmente faz, que é "melhorei?".
    #
    # O cuidado que decide se isso ajuda ou atrapalha: comparar período CORRIDO
    # com período FECHADO mente. No dia 5 de agosto, agosto inteiro contra
    # julho inteiro sugere um colapso de 85% que é só o mês não ter acontecido
    # ainda. Então quando o período atual ainda está rodando, o anterior é
    # truncado no mesmo número de dias — dia 1 a 5 contra dia 1 a 5.
    def build_previous_comparison(car_wash, cost_lookup, current_revenue, current_profit)
      prev_start, prev_end = previous_range(params[:period], @start_date, @end_date)
      return nil if prev_start.nil?

      # Recorte justo: só conta no anterior os mesmos dias já decorridos aqui.
      parcial = @end_date > Date.current && @start_date <= Date.current
      if parcial
        dias_corridos = (Date.current - @start_date).to_i + 1
        prev_end      = [prev_start + dias_corridos - 1, prev_end].min
      end

      prev_revenue = revenue_sum_in_range(car_wash, prev_start, prev_end)
      prev_costs   = costs_for_range_fast(prev_start, prev_end, cost_lookup)
      prev_profit  = prev_revenue - prev_costs[:total]

      {
        start_date:   prev_start.iso8601,
        end_date:     prev_end.iso8601,
        # Diz pro app que a comparação é "até o mesmo dia", pra ele poder
        # rotular. Sem isso o dono não sabe que está vendo recorte.
        partial:      parcial,
        revenue:      prev_revenue.round(2),
        costs_total:  prev_costs[:total].round(2),
        profit:       prev_profit.round(2),
        # Percentual só quando a base é positiva. Variação percentual sobre
        # zero é divisão por zero, e sobre prejuízo dá sinal invertido
        # ("+300%" saindo de -100 pra 200 não comunica nada). Nesses casos o
        # app cai na diferença absoluta, que sempre faz sentido.
        profit_delta:     (current_profit - prev_profit).round(2),
        profit_delta_pct: prev_profit > 0 ? (((current_profit - prev_profit) / prev_profit) * 100).round(1) : nil,
        revenue_delta:     (current_revenue - prev_revenue).round(2),
        revenue_delta_pct: prev_revenue > 0 ? (((current_revenue - prev_revenue) / prev_revenue) * 100).round(1) : nil
      }
    end

    # Janela imediatamente anterior. Por tipo de período em vez de subtrair
    # dias: mês tem 28 a 31 dias, então deslocar por quantidade de dias faria
    # "julho" comparar com "31 de maio a 30 de junho".
    def previous_range(period, start_date, end_date)
      case period
      when "day"
        [start_date - 1, end_date - 1]
      when "week"
        [start_date - 7, end_date - 7]
      when "month"
        anterior = start_date << 1
        [anterior.beginning_of_month, anterior.end_of_month]
      when "year"
        [Date.new(start_date.year - 1, 1, 1), Date.new(start_date.year - 1, 12, 31)]
      when "all"
        nil # "desde o começo" não tem anterior
      else
        span = (end_date - start_date).to_i
        [start_date - span - 1, start_date - 1]
      end
    end

    # Carrega TODOS os monthly_costs relevantes (período + 12 meses pra DRE)
    # numa única query e retorna um hash { [year, month] => MonthlyCost }.
    def build_cost_lookup(car_wash)
      trailing_start_year = 12.months.ago.year
      max_year            = [@end_date.year, Date.current.year].max
      car_wash.monthly_costs
        .where(year: trailing_start_year..max_year)
        .index_by { |c| [c.year, c.month] }
    end

    def revenue_sum_in_range(car_wash, start_date, end_date)
      car_wash.appointments
        .where(status: "attended")
        .where(scheduled_at: start_date.beginning_of_day..end_date.end_of_day)
        .joins(:service)
        .sum("services.price - COALESCE(appointments.commission_amount, 0)").to_f
    end

    def open_revenue_sum_in_range(car_wash, start_date, end_date)
      period_end = end_date.end_of_day
      return 0.0 if period_end < Time.current
      effective_from = [start_date.beginning_of_day, Time.current].max
      car_wash.appointments
        .where(status: "confirmed")
        .where(scheduled_at: effective_from..period_end)
        .joins(:service)
        .sum("services.price - COALESCE(appointments.commission_amount, 0)").to_f
    end

    # Itera por MÊS (não por dia) usando lookup em memória — bem mais rápido
    # que find_by por dia. Para período curto (week/day) ainda é 1-2 iterações.
    def costs_for_range_fast(start_date, end_date, cost_lookup)
      fixed    = 0.0
      variable = 0.0
      cursor   = start_date.beginning_of_month
      while cursor <= end_date
        month_start_in_range = [cursor, start_date].max
        month_end_in_range   = [cursor.end_of_month, end_date].min
        days_overlap         = (month_end_in_range - month_start_in_range).to_i + 1
        days_in_month        = Date.new(cursor.year, cursor.month, -1).day
        mc = cost_lookup[[cursor.year, cursor.month]]
        if mc && days_in_month > 0
          fraction = days_overlap.to_f / days_in_month
          fixed    += mc.total_fixed.to_f    * fraction
          variable += mc.total_variable.to_f * fraction
        end
        cursor = cursor.next_month
      end
      {
        fixed:    fixed.round(2),
        variable: variable.round(2),
        total:    (fixed + variable).round(2)
      }
    end

    def build_chart_series_fast(car_wash, start_date, end_date, granularity, cost_lookup)
      case granularity
      when "hour"
        build_hourly_chart_fast(car_wash, start_date, cost_lookup)
      when "month", "year"
        build_monthly_chart_fast(car_wash, start_date, end_date, cost_lookup)
      else
        build_daily_chart_fast(car_wash, start_date, end_date, cost_lookup)
      end
    end

    def build_hourly_chart_fast(car_wash, day, cost_lookup)
      raw = car_wash.appointments
        .where(status: "attended")
        .where(scheduled_at: day.beginning_of_day..day.end_of_day)
        .joins(:service)
        .group(Arel.sql("EXTRACT(HOUR FROM (scheduled_at AT TIME ZONE 'America/Sao_Paulo'))"))
        .sum("services.price - COALESCE(appointments.commission_amount, 0)")
      rev_by_hour = raw.each_with_object({}) { |(k, v), h| h[k.to_i] = v.to_f }

      mc            = cost_lookup[[day.year, day.month]]
      days_in_month = Date.new(day.year, day.month, -1).day.to_f
      hourly_cost   = mc ? (mc.total.to_f / days_in_month / 24.0) : 0.0

      (0..23).map do |h|
        rev = rev_by_hour[h] || 0.0
        {
          label:   format("%02dh", h),
          revenue: rev.round(2),
          cost:    hourly_cost.round(2),
          profit:  (rev - hourly_cost).round(2)
        }
      end
    end

    def build_daily_chart_fast(car_wash, start_date, end_date, cost_lookup)
      raw = car_wash.appointments
        .where(status: "attended")
        .where(scheduled_at: start_date.beginning_of_day..end_date.end_of_day)
        .joins(:service)
        .group(Arel.sql("DATE(scheduled_at AT TIME ZONE 'America/Sao_Paulo')"))
        .sum("services.price - COALESCE(appointments.commission_amount, 0)")
      rev_by_day = raw.each_with_object({}) do |(k, v), h|
        date = k.is_a?(String) ? Date.parse(k) : k.to_date
        h[date] = v.to_f
      end

      (start_date..end_date).map do |day|
        mc            = cost_lookup[[day.year, day.month]]
        days_in_month = Date.new(day.year, day.month, -1).day.to_f
        daily_cost    = mc ? (mc.total.to_f / days_in_month) : 0.0
        rev           = rev_by_day[day] || 0.0
        {
          label:   day.strftime("%d/%m"),
          revenue: rev.round(2),
          cost:    daily_cost.round(2),
          profit:  (rev - daily_cost).round(2)
        }
      end
    end

    def build_monthly_chart_fast(car_wash, start_date, end_date, cost_lookup)
      raw = car_wash.appointments
        .where(status: "attended")
        .where(scheduled_at: start_date.beginning_of_day..end_date.end_of_day)
        .joins(:service)
        .group(Arel.sql("DATE_TRUNC('month', scheduled_at AT TIME ZONE 'America/Sao_Paulo')"))
        .sum("services.price - COALESCE(appointments.commission_amount, 0)")
      rev_by_month = raw.each_with_object({}) do |(k, v), h|
        date = k.is_a?(String) ? Date.parse(k) : k.to_date
        h[[date.year, date.month]] = v.to_f
      end

      buckets = []
      cursor  = start_date.beginning_of_month
      while cursor <= end_date
        mc         = cost_lookup[[cursor.year, cursor.month]]
        month_cost = mc&.total.to_f
        rev        = rev_by_month[[cursor.year, cursor.month]] || 0.0
        buckets << {
          label:   MonthlyCost::MONTH_NAMES[cursor.month - 1][0..2],
          revenue: rev.round(2),
          cost:    month_cost.round(2),
          profit:  (rev - month_cost).round(2)
        }
        cursor = cursor.next_month
      end
      buckets
    end

    def build_monthly_dre_fast(car_wash, cost_lookup)
      window_start = 11.months.ago.beginning_of_month
      window_end   = Date.current.end_of_month

      rev_raw = car_wash.appointments
        .where(status: "attended")
        .where(scheduled_at: window_start.beginning_of_day..window_end.end_of_day)
        .joins(:service)
        .group(Arel.sql("DATE_TRUNC('month', scheduled_at AT TIME ZONE 'America/Sao_Paulo')"))
        .sum("services.price - COALESCE(appointments.commission_amount, 0)")
      rev_by_month = rev_raw.each_with_object({}) do |(k, v), h|
        date = k.is_a?(String) ? Date.parse(k) : k.to_date
        h[[date.year, date.month]] = v.to_f
      end

      open_raw = car_wash.appointments
        .where(status: "confirmed")
        .where("scheduled_at >= ?", Time.current)
        .where(scheduled_at: Time.current..window_end.end_of_day)
        .joins(:service)
        .group(Arel.sql("DATE_TRUNC('month', scheduled_at AT TIME ZONE 'America/Sao_Paulo')"))
        .sum("services.price - COALESCE(appointments.commission_amount, 0)")
      open_by_month = open_raw.each_with_object({}) do |(k, v), h|
        date = k.is_a?(String) ? Date.parse(k) : k.to_date
        h[[date.year, date.month]] = v.to_f
      end

      (0..11).map do |i|
        date  = i.months.ago
        year  = date.year
        month = date.month
        cost  = cost_lookup[[year, month]]

        revenue      = rev_by_month[[year, month]]  || 0.0
        open_revenue = open_by_month[[year, month]] || 0.0

        fixed      = cost&.total_fixed.to_f
        variable   = cost&.total_variable.to_f
        total_cost = fixed + variable
        profit     = revenue - total_cost
        margin     = revenue > 0 ? ((profit / revenue) * 100).round(1) : nil

        {
          year:            year,
          month:           month,
          label:           "#{MonthlyCost::MONTH_NAMES[month - 1]} #{year}",
          short_label:     "#{MonthlyCost::MONTH_NAMES[month - 1][0..2]}/#{year.to_s[-2..]}",
          revenue:         revenue.round(2),
          open_revenue:    open_revenue.round(2),
          fixed_cost:      fixed.round(2),
          variable_cost:   variable.round(2),
          total_cost:      total_cost.round(2),
          profit:          profit.round(2),
          margin:          margin,
          has_cost_record: cost.present?
        }
      end.reverse
    end

    def build_trailing_12m(monthly_dre)
      revenue    = monthly_dre.sum { |m| m[:revenue] }
      total_cost = monthly_dre.sum { |m| m[:total_cost] }
      profit     = revenue - total_cost
      margins    = monthly_dre.map { |m| m[:margin] }.compact
      avg_margin = margins.any? ? (margins.sum.to_f / margins.size).round(1) : nil
      {
        revenue:     revenue.round(2),
        total_cost:  total_cost.round(2),
        profit:      profit.round(2),
        avg_margin:  avg_margin,
        sparkline:   monthly_dre.map { |m| m[:margin] || 0 }
      }
    end

    def build_period_label(start_date, end_date, period)
      case period
      when "day"    then start_date.strftime("%d/%m/%Y")
      when "week"   then "#{start_date.strftime('%d/%m')} – #{end_date.strftime('%d/%m')}"
      when "month"  then "#{MonthlyCost::MONTH_NAMES[start_date.month - 1]} #{start_date.year}"
      when "year"   then start_date.year.to_s
      when "custom" then "#{start_date.strftime('%d/%m/%y')} – #{end_date.strftime('%d/%m/%y')}"
      when "all"    then "Desde #{start_date.strftime('%d/%m/%Y')}"
      else "#{start_date.strftime('%d/%m')} – #{end_date.strftime('%d/%m')}"
      end
    end
  end
end
