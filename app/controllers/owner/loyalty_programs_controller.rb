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
        exists:             true,
        active:             program.active,
        visits_required:    program.visits_required,
        reward_description: program.reward_description,
        reward_type:        program.reward_type,
        reward_value:       program.reward_value&.to_f,
        reward_service_id:  program.reward_service_id,
        valid_days:         program.valid_days
      } : { exists: false, valid_days: LoyaltyProgram::VALIDADE_PADRAO }
      # Serviços pro "serviço grátis".
      data[:services] = @car_wash.services.order(:price).map { |sv| { id: sv.id, title: sv.title, price: sv.price.to_f } }
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

      # reward_type ausente = versão antiga do app (só o texto): vira brinde.
      tipo = params[:reward_type].presence || (program.persisted? ? program.reward_type : "gift")
      program.assign_attributes(
        visits_required:    params[:visits_required].to_i,
        reward_description: params[:reward_description].to_s.strip.presence || program.reward_description,
        reward_type:        tipo,
        reward_value:       %w[percent fixed].include?(tipo) ? params[:reward_value].presence&.to_s&.tr(",", ".")&.to_d : nil,
        reward_service_id:  tipo == "free_service" ? params[:reward_service_id].presence : nil,
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
                         .where("scheduled_at >= ?", program.created_at).que_contam_carimbo
                         .group(:user_id).count.values
      meta = program.visits_required
      { clientes: visitas.size, recompensas: visitas.sum { |v| v / meta },
        vales: LoyaltyReward.livres.where(car_wash_id: @car_wash.id).count }
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
