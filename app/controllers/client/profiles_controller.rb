module Client
  class ProfilesController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_client

    def show
      redirect_to edit_client_profile_path
    end

    def edit
    end

    def update
      if current_user.update(profile_params)
        redirect_to edit_client_profile_path, notice: "Perfil atualizado com sucesso."
      else
        flash.now[:errors] = current_user.errors.full_messages
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def ensure_client
      redirect_to root_path unless current_user&.client?
    end

    def profile_params
      params.require(:user).permit(:full_name, :phone, :cpf, :vehicle_model)
    end
  end
end
