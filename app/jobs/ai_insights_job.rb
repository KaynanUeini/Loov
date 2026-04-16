class AiInsightsJob < ApplicationJob
  queue_as :default

  def perform(car_wash_id, owner_input = nil)
    car_wash  = CarWash.find(car_wash_id)
    redis     = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    proc_key  = "ai_insights:processing:#{car_wash_id}"
    error_key = "ai_insights:error:#{car_wash_id}"

    begin
      existing        = AiInsight.current_for(car_wash)
      previous_action = existing&.action_of_the_week
      previous_inputs = existing&.previous_inputs_parsed || []

      sections = AiInsightsService.new(car_wash).generate(
        previous_action: previous_action,
        owner_input:     owner_input,
        previous_inputs: previous_inputs
      )

      if existing
        existing.update!(content: sections.to_json, generated_at: Time.current)
      else
        AiInsight.create!(
          car_wash:     car_wash,
          insight_type: "unified",
          content:      sections.to_json,
          generated_at: Time.current
        )
      end

      redis.del(error_key)
    rescue => e
      Rails.logger.error("AiInsightsJob error for car_wash #{car_wash_id}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      redis.set(error_key, e.message, ex: 300)
    ensure
      redis.del(proc_key)
    end
  end
end
