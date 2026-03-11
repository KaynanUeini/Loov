class AiInsight < ApplicationRecord
  belongs_to :car_wash

  REFRESH_DAYS = 15

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

  def action_of_the_week
    JSON.parse(content)["action_of_the_week"]
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
