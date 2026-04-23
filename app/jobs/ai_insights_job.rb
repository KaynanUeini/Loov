class AiInsightsJob < ApplicationJob
  queue_as :default

  def perform(car_wash_id, owner_input = nil)
    car_wash = CarWash.find_by(id: car_wash_id)
    unless car_wash
      Rails.logger.error("AiInsightsJob: car_wash #{car_wash_id} not found")
      return
    end

    insight = AiInsight.current_for(car_wash)
    unless insight
      Rails.logger.error("AiInsightsJob: no AiInsight record for car_wash #{car_wash_id}")
      return
    end

    previous_action = insight.action_of_the_week
    previous_inputs = insight.previous_inputs_parsed

    trace = AiInsightsService.new(car_wash).generate(
      previous_action: previous_action,
      owner_input:     owner_input,
      previous_inputs: previous_inputs
    )

    persist_run(car_wash, insight, trace)
    apply_trace_to_insight(insight, trace)
  end

  private

  def persist_run(car_wash, insight, trace)
    AiInsightRun.create!(
      ai_insight:     insight,
      car_wash:       car_wash,
      status:         trace[:status],
      model:          trace[:model],
      cycle_type:     trace[:cycle_type],
      is_crisis_mode: trace[:is_crisis_mode],
      owner_input:    trace[:owner_input],
      prompt:         trace[:prompt],
      raw_response:   trace[:raw_response],
      parsed_content: trace[:sections],
      parse_ok:       trace[:parse_ok],
      parse_error:    trace[:parse_error],
      input_tokens:   trace[:input_tokens],
      output_tokens:  trace[:output_tokens],
      latency_ms:     trace[:latency_ms],
      error_message:  trace[:error_message],
    )
  rescue => e
    Rails.logger.error("AiInsightsJob: failed to persist run — #{e.class}: #{e.message}")
  end

  def apply_trace_to_insight(insight, trace)
    if trace[:sections].present?
      insight.update!(
        content:       trace[:sections].to_json,
        generated_at:  Time.current,
        status:        "ready",
        error_message: nil,
      )
    else
      insight.update_columns(
        status:        "error",
        error_message: trace[:error_message] || "Falha desconhecida na geração da análise.",
      )
    end
  rescue => e
    Rails.logger.error("AiInsightsJob update error: #{e.message}")
    insight.update_columns(status: "error", error_message: e.message)
  end
end
