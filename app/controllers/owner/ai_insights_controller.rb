module Owner
  class AiInsightsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner

    # GET /owner/ai_insights — initial load, returns all sections at once
    def show
      car_wash = current_user.car_washes.first
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found if car_wash.nil?

      existing = AiInsight.current_for(car_wash)

      if existing && !cycle_expired?(existing)
        render json: full_insight_response(existing, cached: true)
      else
        render json: { status: "needs_generation", days_remaining: 0 }
      end
    end

    # POST /owner/ai_insights — enqueues generation job or returns cached data
    def create
      car_wash = current_user.car_washes.first
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found if car_wash.nil?

      force    = params[:force] == "true"
      existing = AiInsight.current_for(car_wash)

      # Return cached immediately when valid and not forced
      if existing && !cycle_expired?(existing) && !force
        return render json: full_insight_response(existing, cached: true)
      end

      # Capture owner_input before archiving clears it
      owner_input = existing&.owner_input
      existing&.archive_input!

      redis = redis_client
      redis.set("ai_insights:processing:#{car_wash.id}", "1", ex: 600)
      redis.del("ai_insights:error:#{car_wash.id}")

      AiInsightsJob.perform_later(car_wash.id, owner_input)

      render json: { status: "processing" }
    end

    # GET /owner/ai_insights/status — polling endpoint
    def status
      car_wash = current_user.car_washes.first
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found if car_wash.nil?

      redis = redis_client

      if redis.get("ai_insights:processing:#{car_wash.id}")
        return render json: { status: "processing" }
      end

      if (err = redis.get("ai_insights:error:#{car_wash.id}"))
        return render json: { status: "error", message: err }
      end

      existing = AiInsight.current_for(car_wash)

      if existing && !cycle_expired?(existing)
        render json: full_insight_response(existing, cached: false)
      else
        render json: { status: "needs_generation" }
      end
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

    def redis_client
      Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    end
  end
end
