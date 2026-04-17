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

    begin
      # Read previous data from the still-intact content field before overwriting
      previous_action = insight.action_of_the_week
      previous_inputs = insight.previous_inputs_parsed

      sections = AiInsightsService.new(car_wash).generate(
        previous_action: previous_action,
        owner_input:     owner_input,
        previous_inputs: previous_inputs
      )

      insight.update!(
        content:       sections.to_json,
        generated_at:  Time.current,
        status:        "ready",
        error_message: nil
      )
    rescue => e
      Rails.logger.error("AiInsightsJob error for car_wash #{car_wash_id}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      insight.update_columns(status: "error", error_message: e.message)
    end
  end
end
