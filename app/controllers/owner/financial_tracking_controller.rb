module Owner
  class FinancialTrackingController < ApplicationController
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
  end
end
