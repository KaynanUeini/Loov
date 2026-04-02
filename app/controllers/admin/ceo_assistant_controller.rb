module Admin
  class CeoAssistantController < Admin::BaseController
    def analyze
      focus   = params[:focus].presence
      service = CeoAssistantService.new
      result  = service.generate_briefing(focus: focus)

      if result[:error]
        render json: { ok: false, error: result[:error] }, status: :unprocessable_entity
      else
        render json: { ok: true, briefing: result[:briefing], generated_at: result[:generated_at] }
      end
    end
  end
end
