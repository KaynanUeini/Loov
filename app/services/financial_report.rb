# Relatório financeiro detalhado de um período — a versão "aberta" do que a
# tela de Financeiro mostra em totais. Alimenta o JSON (o app monta o PDF) e
# a planilha .xlsx (FinancialReportXlsx).
#
# Regra que manda em tudo aqui: os totais têm que bater centavo a centavo com
# a tela de Financeiro do mesmo período. Por isso a receita usa
# Appointment::NET_REVENUE_SQL e os custos são rateados por dia exatamente
# como em FinancialTrackingController#costs_for_range_fast.
class FinancialReport
  # Campos padrão do MonthlyCost, com os rótulos que o dono vê no app.
  # `utilities` é o campo legado de água+luz: o app exibe ele dentro de "Luz",
  # então aqui ele soma na mesma linha.
  STANDARD_COSTS = [
    { field: :rent,           key: "rent",           label: "Aluguel",          type: "fixed"    },
    { field: :salaries,       key: "salaries",       label: "Salários",         type: "fixed"    },
    { field: :water,          key: "water",          label: "Água",             type: "fixed"    },
    { field: :electricity,    key: "electricity",    label: "Luz",              type: "fixed"    },
    { field: :utilities,      key: "electricity",    label: "Luz",              type: "fixed"    },
    { field: :other_fixed,    key: "other_fixed",    label: "Outros fixos",     type: "fixed"    },
    { field: :products,       key: "products",       label: "Produtos",         type: "variable" },
    { field: :maintenance,    key: "maintenance",    label: "Manutenção",       type: "variable" },
    { field: :other_variable, key: "other_variable", label: "Outros variáveis", type: "variable" }
  ].freeze

  CHANNELS = {
    # Mesmos nomes que o dono vê no app e no site: "Agendamento" e "Last Minute".
    "app"        => "Agendamento",
    "disponivel" => "Last Minute",
    "walk_in"    => "Avulso"
  }.freeze

  attr_reader :car_wash, :start_date, :end_date, :period, :period_label

  def initialize(car_wash:, start_date:, end_date:, period:, period_label:)
    @car_wash     = car_wash
    @start_date   = start_date
    @end_date     = end_date
    @period       = period
    @period_label = period_label
  end

  def as_json(*)
    data
  end

  def data
    @data ||= build
  end

  private

  def build
    rows     = appointment_rows
    services = revenue_by_service(rows)
    channels = revenue_by_channel(rows)
    costs    = cost_breakdown

    revenue    = rows.sum { |r| r[:net] }
    gross      = rows.sum { |r| r[:gross] }
    commission = rows.sum { |r| r[:commission] }
    profit     = revenue - costs[:total]

    {
      car_wash: {
        name:    car_wash.name,
        address: [car_wash.try(:logradouro), car_wash.try(:cidade)].compact_blank.join(" · ").presence || car_wash.address
      },
      period:       period,
      period_label: period_label,
      start_date:   start_date.iso8601,
      end_date:     end_date.iso8601,
      generated_at: Time.current.iso8601,
      summary: {
        revenue:        revenue.round(2),
        gross_revenue:  gross.round(2),
        commission:     commission.round(2),
        open_revenue:   open_revenue.round(2),
        costs_total:    costs[:total],
        fixed_cost:     costs[:fixed_total],
        variable_cost:  costs[:variable_total],
        profit:         profit.round(2),
        margin:         revenue > 0 ? ((profit / revenue) * 100).round(1) : nil,
        attended_count: rows.size,
        avg_ticket:     rows.any? ? (revenue / rows.size).round(2) : 0.0
      },
      revenue_by_service: services,
      revenue_by_channel: channels,
      costs:              costs,
      monthly:            monthly_breakdown(rows),
      appointments:       rows.map { |r| r.except(:month_key) }
    }
  end

  # ── Receita ────────────────────────────────────────────────────────────────

  def attended_scope
    car_wash.appointments
      .where(status: "attended")
      .where(scheduled_at: start_date.beginning_of_day..end_date.end_of_day)
  end

  # Uma linha por atendimento. Carregado uma vez e agregado em Ruby: o mesmo
  # conjunto alimenta serviço, canal, mês e a lista, então não tem como um
  # total divergir do outro.
  def appointment_rows
    attended_scope
      .includes(:service, :user)
      .order(:scheduled_at)
      .map do |a|
        gross      = a.effective_price
        commission = a.commission_amount.to_f
        local      = a.scheduled_at.in_time_zone
        {
          id:          a.id,
          date:        local.to_date.iso8601,
          time:        local.strftime("%H:%M"),
          client:      a.display_client,
          service_id:  a.service_id,
          service:     a.service&.title || "Serviço removido",
          category:    a.service&.category,
          channel:     channel_for(a),
          price_adjusted: a.price_override.present?,
          gross:       gross.round(2),
          commission:  commission.round(2),
          net:         (gross - commission).round(2),
          month_key:   [local.year, local.month]
        }
      end
  end

  def channel_for(appointment)
    return "disponivel" if appointment.disponivel?
    return "walk_in"    if appointment.walk_in?
    "app"
  end

  def revenue_by_service(rows)
    total = rows.sum { |r| r[:net] }
    rows.group_by { |r| [r[:service_id], r[:service]] }.map do |(_, title), list|
      net = list.sum { |r| r[:net] }
      {
        service:    title,
        category:   list.first[:category],
        count:      list.size,
        gross:      list.sum { |r| r[:gross] }.round(2),
        commission: list.sum { |r| r[:commission] }.round(2),
        net:        net.round(2),
        avg_ticket: (net / list.size).round(2),
        share:      total > 0 ? ((net / total) * 100).round(1) : 0.0
      }
    end.sort_by { |s| [-s[:net], -s[:count]] }
  end

  def revenue_by_channel(rows)
    total = rows.sum { |r| r[:net] }
    CHANNELS.filter_map do |key, label|
      list = rows.select { |r| r[:channel] == key }
      next if list.empty?
      net = list.sum { |r| r[:net] }
      {
        channel:    key,
        label:      label,
        count:      list.size,
        commission: list.sum { |r| r[:commission] }.round(2),
        net:        net.round(2),
        share:      total > 0 ? ((net / total) * 100).round(1) : 0.0
      }
    end
  end

  def open_revenue
    period_end = end_date.end_of_day
    return 0.0 if period_end < Time.current
    car_wash.appointments
      .where(status: "confirmed")
      .where(scheduled_at: [start_date.beginning_of_day, Time.current].max..period_end)
      .joins(:service)
      .sum(Appointment::NET_REVENUE_SQL).to_f
  end

  # ── Custos ─────────────────────────────────────────────────────────────────

  def cost_records
    @cost_records ||= car_wash.monthly_costs
      .includes(:custom_cost_lines)
      .where(year: start_date.year..end_date.year)
      .index_by { |c| [c.year, c.month] }
  end

  # Meses tocados pelo período, com a fração de dias que cai dentro dele.
  # Semana de 7 dias em julho leva 7/31 do custo de julho — mesma regra do
  # gráfico.
  def months_in_range
    @months_in_range ||= begin
      list   = []
      cursor = start_date.beginning_of_month
      while cursor <= end_date
        from = [cursor, start_date].max
        to   = [cursor.end_of_month, end_date].min
        list << {
          year:     cursor.year,
          month:    cursor.month,
          fraction: ((to - from).to_i + 1).to_f / cursor.end_of_month.day
        }
        cursor = cursor.next_month
      end
      list
    end
  end

  def cost_breakdown
    lines = {}

    add = lambda do |key, label, type, amount|
      return if amount.to_f.zero?
      line = (lines[[type, key]] ||= { key: key, label: label, type: type, amount: 0.0 })
      line[:amount] += amount.to_f
    end

    months_in_range.each do |m|
      mc = cost_records[[m[:year], m[:month]]]
      next unless mc

      STANDARD_COSTS.each do |c|
        add.call(c[:key], c[:label], c[:type], mc.public_send(c[:field]).to_f * m[:fraction])
      end
      # Linhas criadas pelo dono: agrupa pelo nome (sem caixa/acento) pra
      # "Internet" de julho e "internet" de agosto virarem uma linha só.
      mc.custom_cost_lines.sort_by { |l| [l.position || 0, l.id] }.each do |l|
        key = "custom:#{I18n.transliterate(l.name.to_s.strip.downcase)}"
        add.call(key, l.name.to_s.strip, l.cost_type, l.amount.to_f * m[:fraction])
      end
    end

    fixed    = lines.values.select { |l| l[:type] == "fixed" }.sum { |l| l[:amount] }
    variable = lines.values.select { |l| l[:type] == "variable" }.sum { |l| l[:amount] }
    total    = fixed + variable

    {
      lines: lines.values
        .map { |l| l.merge(amount: l[:amount].round(2), share: total > 0 ? ((l[:amount] / total) * 100).round(1) : 0.0) }
        .sort_by { |l| [l[:type] == "fixed" ? 0 : 1, -l[:amount]] },
      fixed_total:    fixed.round(2),
      variable_total: variable.round(2),
      total:          total.round(2),
      # Período que não cobre o mês inteiro leva só a fração dos dias. O
      # relatório avisa, senão o dono estranha "Aluguel R$ 451,61".
      prorated:       months_in_range.any? { |m| m[:fraction] < 1 },
      # Mês que ainda não começou não "falta" — o dono não tinha como lançar.
      months_without_costs: months_in_range
        .reject { |m| cost_records.key?([m[:year], m[:month]]) }
        .reject { |m| Date.new(m[:year], m[:month], 1) > Date.current }
        .map { |m| "#{MonthlyCost::MONTH_NAMES[m[:month] - 1]} #{m[:year]}" }
    }
  end

  # ── Mês a mês (só quando o período atravessa mais de um mês) ──────────────

  def monthly_breakdown(rows)
    return [] if months_in_range.size < 2

    by_month = rows.group_by { |r| r[:month_key] }
    months_in_range.map do |m|
      list    = by_month[[m[:year], m[:month]]] || []
      revenue = list.sum { |r| r[:net] }
      mc      = cost_records[[m[:year], m[:month]]]
      cost    = mc ? mc.total.to_f * m[:fraction] : 0.0
      profit  = revenue - cost
      {
        label:   "#{MonthlyCost::MONTH_NAMES[m[:month] - 1]} #{m[:year]}",
        count:   list.size,
        revenue: revenue.round(2),
        costs:   cost.round(2),
        profit:  profit.round(2),
        margin:  revenue > 0 ? ((profit / revenue) * 100).round(1) : nil
      }
    end
  end
end
