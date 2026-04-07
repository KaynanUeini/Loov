module Owner
  class LoyaltyProgramsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_owner
    before_action :set_car_wash

    # GET /owner/loyalty_program
    def show
      program = @car_wash.loyalty_program
      render json: program ? {
        exists:           true,
        active:           program.active,
        visits_required:  program.visits_required,
        reward_description: program.reward_description
      } : { exists: false }
    end

    # POST /owner/loyalty_program
    def upsert
      program = @car_wash.loyalty_program || @car_wash.build_loyalty_program

      program.assign_attributes(
        visits_required:    params[:visits_required].to_i,
        reward_description: params[:reward_description].to_s.strip,
        active:             params[:active] != false && params[:active] != "false"
      )

      if program.save
        render json: { ok: true }
      else
        render json: { ok: false, error: program.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    private

    def set_car_wash
      @car_wash = current_car_wash
      render json: { ok: false, error: "Lava-rápido não encontrado." }, status: :not_found unless @car_wash
    end

    def ensure_owner
      render json: { ok: false, error: "Acesso negado." }, status: :forbidden unless current_user&.owner?
    end
  end
end
