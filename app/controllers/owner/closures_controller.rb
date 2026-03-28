module Owner
  class ClosuresController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_owner

    def create
      car_wash = current_user.car_washes.first
      closure  = car_wash.closures.build(closure_params)

      if closure.save
        render json: { ok: true, id: closure.id }
      else
        render json: { ok: false, errors: closure.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      car_wash = current_user.car_washes.first
      closure  = car_wash.closures.find(params[:id])
      closure.destroy
      render json: { ok: true }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "Bloqueio não encontrado." }, status: :not_found
    end

    private

    def closure_params
      params.require(:closure).permit(:starts_at, :ends_at, :reason)
    end

    def ensure_owner
      unless current_user&.owner?
        render json: { error: "Acesso restrito a proprietários." }, status: :forbidden
      end
    end
  end
end
