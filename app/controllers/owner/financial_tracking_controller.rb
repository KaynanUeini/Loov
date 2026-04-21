module Owner
  class FinancialTrackingController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner

    def index
      car_wash = current_user.car_washes.first
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

      # ── BASE: apenas atendimentos efetivados pelo dono ─────────────────────
      base = car_wash.appointments
      .where(status: "attended")
      .where(scheduled_at: @start_date.beginning_of_day..@end_date.end_of_day)
      .joins(:service)

      base = base.where("services.title = ?", params[:service_filter]) if params[:service_filter].present?

      @appointments       = base
      @total_sales        = @appointments.sum("services.price").to_f
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
      .select("DATE(scheduled_at) AS sale_date, COUNT(*) AS appointment_count, SUM(services.price) AS total_value")
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
      .select("DATE_TRUNC('month', scheduled_at) AS period_start, COUNT(*) AS appointment_count, SUM(services.price) AS total_value")
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
      .select("DATE_TRUNC('year', scheduled_at) AS period_start, COUNT(*) AS appointment_count, SUM(services.price) AS total_value")
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
        .select("DATE(scheduled_at - INTERVAL '3 hours'), EXTRACT(HOUR FROM (scheduled_at - INTERVAL '3 hours')) AS sale_hour, COUNT(*) AS appointment_count, SUM(services.price) AS total_value")
        .order(Arel.sql("DATE(scheduled_at - INTERVAL '3 hours') ASC, sale_hour ASC"))
        @chart_data = sales_by_hour.map { |e| { date: "#{e.sale_hour.to_i}:00", value: e.total_value.to_f } }

        confirmed_by_hour = confirmed_base
        .group(Arel.sql("DATE(scheduled_at - INTERVAL '3 hours'), EXTRACT(HOUR FROM (scheduled_at - INTERVAL '3 hours'))"))
        .select("DATE(scheduled_at - INTERVAL '3 hours'), EXTRACT(HOUR FROM (scheduled_at - INTERVAL '3 hours')) AS sale_hour, SUM(services.price) AS total_value")
        .order(Arel.sql("DATE(scheduled_at - INTERVAL '3 hours') ASC, sale_hour ASC"))
        confirmed_map = confirmed_by_hour.each_with_object({}) { |e, h| h["#{e.sale_hour.to_i}:00"] = e.total_value.to_f }
        @confirmed_chart_data = @chart_data.map { |d| { date: d[:date], value: confirmed_map[d[:date]] || 0 } }
      when "day"
        @chart_data = @sales_by_day.map { |e| { date: e.sale_date.strftime("%d/%m"), value: e.total_value.to_f } }

        confirmed_by_day = confirmed_base
        .group(Arel.sql("DATE(scheduled_at)"))
        .select("DATE(scheduled_at) AS sale_date, SUM(services.price) AS total_value")
        .order(Arel.sql("DATE(scheduled_at) ASC"))
        confirmed_map = confirmed_by_day.each_with_object({}) { |e, h| h[e.sale_date.strftime("%d/%m")] = e.total_value.to_f }
        @confirmed_chart_data = @chart_data.map { |d| { date: d[:date], value: confirmed_map[d[:date]] || 0 } }

      when "month"
        @chart_data = @sales_by_month.map { |e| { date: (I18n.l(e.period_start, format: "%b/%Y", locale: :"pt-BR") rescue e.period_start.strftime("%m/%Y")), value: e.total_value.to_f } }

        confirmed_by_month = confirmed_base
        .group(Arel.sql("DATE_TRUNC('month', scheduled_at)"))
        .select("DATE_TRUNC('month', scheduled_at) AS period_start, SUM(services.price) AS total_value")
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
        .select("DATE_TRUNC('year', scheduled_at) AS period_start, SUM(services.price) AS total_value")
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
      .select("services.title, COUNT(*) AS total_count, SUM(services.price) AS total_revenue")
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

      # ── RESPOSTA JSON (consumida pelo app mobile) ──────────────────────────
      respond_to do |format|
        format.html   # renderiza view erb normalmente
        format.json do
          render json: build_financial_json(car_wash)
        end
      end
    end

    private

    def ensure_owner
      unless current_user&.owner?
        redirect_to root_path, alert: "Acesso restrito a donos de lava-rápidos."
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

    # ── Novo shape JSON (v2 — DRE completo, KPIs, chart com 3 séries) ─────
    # Mantém o caminho HTML intacto. As @variáveis do HTML continuam sendo
    # computadas acima; aqui só construímos um payload novo.

    def build_financial_json(car_wash)
      revenue      = @total_sales.to_f
      open_revenue = compute_open_revenue(car_wash, @start_date, @end_date)
      costs        = compute_period_costs(car_wash, @start_date, @end_date)
      profit       = revenue - costs[:total]
      margin       = revenue > 0 ? ((profit / revenue) * 100).round(1) : nil

      chart        = build_chart_series(car_wash, @start_date, @end_date, @granularity)
      monthly_dre  = build_monthly_dre(car_wash)
      trailing     = build_trailing_12m(monthly_dre)

      {
        period:        params[:period] || "month",
        period_label:  build_period_label(@start_date, @end_date, params[:period]),
        start_date:    @start_date.iso8601,
        end_date:      @end_date.iso8601,
        granularity:   @granularity,
        kpis: {
          revenue:      revenue.round(2),
          open_revenue: open_revenue.round(2),
          costs:        costs,
          profit:       profit.round(2),
          margin:       margin
        },
        chart:         chart,
        monthly_dre:   monthly_dre,
        trailing_12m:  trailing
      }
    end

    # Receita "em aberto" = agendamentos confirmed que ainda não aconteceram,
    # dentro da janela do período filtrado. Se o período já passou inteiro,
    # retorna 0 (não faz sentido "em aberto" no passado).
    def compute_open_revenue(car_wash, start_date, end_date)
      period_end = end_date.end_of_day
      return 0.0 if period_end < Time.current

      effective_from = [start_date.beginning_of_day, Time.current].max
      car_wash.appointments
        .where(status: "confirmed")
        .where(scheduled_at: effective_from..period_end)
        .joins(:service)
        .sum("services.price").to_f
    end

    # Soma os custos dos meses que se sobrepõem ao período, pró-ratando o
    # custo mensal pelos dias dentro do intervalo. Ex: filtro de 15 dias em
    # abril soma (15/30) * custo_abril. Retorna fixo/variável/total.
    def compute_period_costs(car_wash, start_date, end_date)
      fixed = 0.0
      variable = 0.0
      (start_date..end_date).each do |day|
        mc = car_wash.monthly_costs.find_by(year: day.year, month: day.month)
        next unless mc
        days_in_month = Date.new(day.year, day.month, -1).day.to_f
        fixed    += mc.total_fixed.to_f / days_in_month
        variable += mc.total_variable.to_f / days_in_month
      end
      {
        fixed:    fixed.round(2),
        variable: variable.round(2),
        total:    (fixed + variable).round(2)
      }
    end

    def build_chart_series(car_wash, start_date, end_date, granularity)
      case granularity
      when "hour"
        build_hourly_chart(car_wash, start_date)
      when "month", "year"
        build_monthly_chart(car_wash, start_date, end_date)
      else
        build_daily_chart(car_wash, start_date, end_date)
      end
    end

    def build_hourly_chart(car_wash, day)
      mc            = car_wash.monthly_costs.find_by(year: day.year, month: day.month)
      days_in_month = Date.new(day.year, day.month, -1).day.to_f
      hourly_cost   = mc ? (mc.total.to_f / days_in_month / 24.0) : 0.0
      (0..23).map do |h|
        bucket_start = day.in_time_zone.change(hour: h, min: 0, sec: 0)
        bucket_end   = bucket_start + 59.minutes + 59.seconds
        rev = car_wash.appointments
          .where(status: "attended", scheduled_at: bucket_start..bucket_end)
          .joins(:service).sum("services.price").to_f
        {
          label:   format("%02dh", h),
          revenue: rev.round(2),
          cost:    hourly_cost.round(2),
          profit:  (rev - hourly_cost).round(2)
        }
      end
    end

    def build_daily_chart(car_wash, start_date, end_date)
      (start_date..end_date).map do |day|
        mc            = car_wash.monthly_costs.find_by(year: day.year, month: day.month)
        days_in_month = Date.new(day.year, day.month, -1).day.to_f
        daily_cost    = mc ? (mc.total.to_f / days_in_month) : 0.0
        rev = car_wash.appointments
          .where(status: "attended", scheduled_at: day.beginning_of_day..day.end_of_day)
          .joins(:service).sum("services.price").to_f
        {
          label:   day.strftime("%d/%m"),
          revenue: rev.round(2),
          cost:    daily_cost.round(2),
          profit:  (rev - daily_cost).round(2)
        }
      end
    end

    def build_monthly_chart(car_wash, start_date, end_date)
      buckets = []
      cursor  = start_date.beginning_of_month
      while cursor <= end_date
        month_end  = [cursor.end_of_month, end_date].min
        mc         = car_wash.monthly_costs.find_by(year: cursor.year, month: cursor.month)
        month_cost = mc&.total.to_f
        rev = car_wash.appointments
          .where(status: "attended", scheduled_at: cursor.beginning_of_day..month_end.end_of_day)
          .joins(:service).sum("services.price").to_f
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

    def build_monthly_dre(car_wash)
      (0..11).map do |i|
        date   = i.months.ago
        year   = date.year
        month  = date.month
        cost   = car_wash.monthly_costs.find_by(year: year, month: month)

        month_start = date.beginning_of_month
        month_end   = date.end_of_month

        revenue = car_wash.appointments
          .where(status: "attended")
          .joins(:service)
          .where(scheduled_at: month_start.beginning_of_day..month_end.end_of_day)
          .sum("services.price").to_f

        open_from = [month_start.beginning_of_day, Time.current].max
        open_revenue = if month_end.end_of_day < Time.current
          0.0
        else
          car_wash.appointments
            .where(status: "confirmed")
            .joins(:service)
            .where(scheduled_at: open_from..month_end.end_of_day)
            .sum("services.price").to_f
        end

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
