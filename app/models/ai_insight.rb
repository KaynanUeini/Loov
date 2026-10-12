class AiInsight < ApplicationRecord
  belongs_to :car_wash
  has_many   :runs, class_name: "AiInsightRun", dependent: :nullify

  REFRESH_DAYS = 15
  STATUSES     = %w[processing ready error].freeze

  def processing? = status == "processing"
  def ready?      = status == "ready"
  def error?      = status == "error"

  # ── Ciclos da análise ────────────────────────────────────────────────────
  # Abrem no dia 15 e no último dia do mês: os dois momentos em que o dono
  # fecha a quinzena e o mês, com o caixa e os custos do período na mão. O
  # aviso pro dono (AiInsightReminders) sai nesses mesmos dias. Uma regra só,
  # usada pelo controller, pelo serviço e pelo aviso — antes cada um tinha a
  # sua cópia, com ciclo começando no dia 1.
  def self.inicio_do_ciclo(dia = Date.current)
    return dia if dia == dia.end_of_month
    dia.day >= 15 ? dia.change(day: 15) : dia.prev_month.end_of_month
  end

  def self.proximo_ciclo(dia = Date.current)
    return dia.next_month.change(day: 15) if dia == dia.end_of_month
    dia.day < 15 ? dia.change(day: 15) : dia.end_of_month
  end

  def self.dia_de_ciclo?(dia = Date.current)
    dia.day == 15 || dia == dia.end_of_month
  end

  def self.current_for(car_wash)
    where(car_wash: car_wash, insight_type: "unified")
      .order(generated_at: :desc)
      .first
  end

  def expired?
    generated_at < REFRESH_DAYS.days.ago
  end

  def next_refresh
    (generated_at + REFRESH_DAYS.days).strftime("%d/%m/%Y")
  end

  def days_remaining
    days = ((generated_at + REFRESH_DAYS.days) - Time.current) / 1.day
    [days.ceil, 0].max
  end

  # Suporta formato antigo (string) e novo (hash com text/status)
  def section(type)
    parsed = JSON.parse(content)
    value  = parsed[type.to_s]
    return nil unless value
    value.is_a?(Hash) ? value["text"] : value
  rescue
    nil
  end

  def section_status(type)
    parsed = JSON.parse(content)
    value  = parsed[type.to_s]
    return "stable" unless value.is_a?(Hash)
    value["status"] || "stable"
  rescue
    "stable"
  end

  def cycle_summary
    JSON.parse(content)["cycle_summary"]
  rescue
    nil
  end

  # Suporta tanto o campo novo (decisao_prioritaria) quanto o legado (action_of_the_week)
  # para manter compatibilidade com análises já geradas anteriormente
  def action_of_the_week
    parsed = JSON.parse(content)
    parsed["decisao_prioritaria"] || parsed["action_of_the_week"]
  rescue
    nil
  end

  def archive_input!
    return unless owner_input.present?
    history = previous_inputs_parsed
    history.unshift({ text: owner_input, saved_at: owner_input_at&.strftime("%d/%m/%Y") })
    history = history.first(3)
    update_columns(
      previous_inputs: history.to_json,
      owner_input:     nil,
      owner_input_at:  nil
    )
  end

  def previous_inputs_parsed
    return [] unless previous_inputs.present?
    JSON.parse(previous_inputs)
  rescue
    []
  end
end
