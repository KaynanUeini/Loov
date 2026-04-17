module Owner
  class AiInsightsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner

    # GET /owner/ai_insights — initial load
    def show
      car_wash = current_user.car_washes.first
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found if car_wash.nil?

      render json: insight_status_response(car_wash, cached: true)
    end

    # POST /owner/ai_insights — synchronous generation or return cached
    def create
      car_wash = current_user.car_washes.first
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found if car_wash.nil?

      force    = params[:force] == "true"
      existing = AiInsight.current_for(car_wash)

      if existing&.ready? && !cycle_expired?(existing) && !force
        return render json: full_insight_response(existing, cached: true)
      end

      owner_input = existing&.owner_input
      existing&.archive_input!

      begin
        Rack::Timeout.timeout(180) do
          sections = AiInsightsService.new(car_wash).generate(
            previous_action: existing&.action_of_the_week,
            owner_input:     owner_input,
            previous_inputs: existing&.previous_inputs_parsed || []
          )

          if existing
            existing.update!(content: sections.to_json, status: "ready", generated_at: Time.current, error_message: nil)
          else
            existing = AiInsight.create!(
              car_wash:     car_wash,
              insight_type: "unified",
              status:       "ready",
              generated_at: Time.current,
              content:      sections.to_json
            )
          end

          render json: full_insight_response(existing, cached: false)
        end
      rescue => e
        Rails.logger.error("AI Insights error: #{e.message}")
        render json: { error: "Não foi possível gerar a análise.", detail: e.message }, status: :unprocessable_entity
      end
    end

    # GET /owner/ai_insights/status — polling endpoint
    def status
      car_wash = current_user.car_washes.first
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found if car_wash.nil?

      render json: insight_status_response(car_wash, cached: false)
    end

    # POST /owner/ai_insights/input — save owner focus text
    def input
      car_wash = current_user.car_washes.first
      existing = AiInsight.current_for(car_wash)
      return render json: { error: "Nenhuma análise encontrada." }, status: :not_found unless existing
      existing.update!(owner_input: params[:input], owner_input_at: Time.current)
      render json: { ok: true }
    end

    private

    def ensure_owner
      render json: { error: "Acesso negado." }, status: :forbidden unless current_user&.owner?
    end

    # ── CICLO ─────────────────────────────────────────────────────────────────

    def current_cycle_start
      today = Date.current
      today.day >= 15 ? Date.new(today.year, today.month, 15) : Date.new(today.year, today.month, 1)
    end

    def cycle_expired?(insight)
      insight.generated_at.to_date < current_cycle_start
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

    # ── HELPERS ───────────────────────────────────────────────────────────────

    def insight_status_response(car_wash, cached:)
      existing = AiInsight.current_for(car_wash)

      return { status: "needs_generation" } unless existing

      if existing.processing?
        { status: "processing" }
      elsif existing.error?
        { status: "error", message: existing.error_message || "Não foi possível gerar a análise." }
      elsif cycle_expired?(existing)
        { status: "needs_generation" }
      else
        full_insight_response(existing, cached: cached)
      end
    end

    def full_insight_response(insight, cached:)
      content  = JSON.parse(insight.content) rescue {}
      sections = {}

      %w[sales services clients demand retention growth].each do |type|
        val = content[type]
        sections[type] = {
          text:   val.is_a?(Hash) ? val["text"] : val.to_s,
          status: val.is_a?(Hash) ? (val["status"] || "stable") : "stable"
        }
      end

      {
        status:              "ready",
        sections:            sections,
        decisao_prioritaria: content["decisao_prioritaria"] || insight.action_of_the_week || "",
        cycle_summary:       content["cycle_summary"]       || insight.cycle_summary       || "",
        generated_at:        insight.generated_at.strftime("%d/%m/%Y"),
        next_refresh:        next_cycle_date,
        days_remaining:      days_until_next_cycle,
        has_input:           insight.owner_input.present?,
        cached:              cached
      }
    end
  end
end
