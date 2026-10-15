module Owner
  # GET /owner/profile_summary — o que o Perfil do app do dono/atendente
  # mostra no topo, igual ao Perfil do site (Users::RegistrationsController
  # #load_staff_account): os dois números do cartão escuro e o lava-rápido.
  class ProfileSummariesController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!

    def show
      unless current_user.owner? || current_user.attendant?
        return render json: { error: "Acesso negado." }, status: :forbidden
      end

      cw = current_user.linked_car_wash
      render json: {
        name:     current_user.full_name,
        email:    current_user.email,
        role:     current_user.role,
        car_wash: cw && { id: cw.id, name: cw.name, address: cw.endereco_curto },
        resumo:   cw ? cw.resumo_perfil : { today: 0, month_attended: 0 }
      }
    end
  end
end
