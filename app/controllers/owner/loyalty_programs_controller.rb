module Owner
  class LoyaltyProgramsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner
    before_action :set_car_wash

    # GET /owner/loyalty_program — JSON pro app; no site, a página do
    # Programa de fidelidade com o programa e os números embutidos.
    def show
      program = @car_wash.loyalty_program
      data = program ? {
        exists:           true,
        active:           program.active,
        visits_required:  program.visits_required,
        reward_description: program.reward_description
      } : { exists: false }
      respond_to do |format|
        format.html do
          @program_json = data
          @stats = program ? numeros(program) : nil
        end
        format.json { render json: data }
      end
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

    # Clientes com ao menos um carimbo e recompensas já ganhas — a mesma
    # conta do cartão (LoyaltyProgram#cartao_para), só que de todos de uma vez.
    def numeros(program)
      visitas = @car_wash.appointments.where(status: "attended").where.not(user_id: nil)
                         .where("scheduled_at >= ?", program.created_at)
                         .group(:user_id).count.values
      meta = program.visits_required
      { clientes: visitas.size, recompensas: visitas.sum { |v| v / meta } }
    end

    def set_car_wash
      @car_wash = current_car_wash
      return if @car_wash
      return redirect_to(root_path) if request.format.html?
      render json: { ok: false, error: "Lava-rápido não encontrado." }, status: :not_found
    end

    def ensure_owner
      return if current_user&.owner?
      return redirect_to(root_path) if request.format.html?
      render json: { ok: false, error: "Acesso negado." }, status: :forbidden
    end
  end
end
