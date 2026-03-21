module Client
  class ProfilesController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_client

    def show
      redirect_to edit_client_profile_path
    end

    def edit
      # setup_intent para cadastrar cartão novo
      if current_user.stripe_customer_id.present? || params[:add_card]
        customer = current_user.stripe_customer!
        @setup_intent = Stripe::SetupIntent.create(
          customer:            customer.id,
          payment_method_types: ["card"],
          usage:               "off_session"  # para cobranças futuras sem o cliente presente
        )
        @setup_client_secret = @setup_intent.client_secret
      end
    rescue Stripe::StripeError => e
      Rails.logger.error("ProfilesController#edit Stripe error: #{e.message}")
      @setup_client_secret = nil
    end

    def update
      if current_user.update(profile_params)
        redirect_to edit_client_profile_path, notice: "Perfil atualizado com sucesso."
      else
        flash.now[:errors] = current_user.errors.full_messages
        render :edit, status: :unprocessable_entity
      end
    end

    # POST /client/profile/attach_payment_method
    # Recebe o payment_method_id confirmado pelo Stripe.js no frontend
    # e salva no usuário
    def attach_payment_method
      payment_method_id = params[:payment_method_id]

      if payment_method_id.blank?
        render json: { error: "payment_method_id é obrigatório" }, status: :unprocessable_entity
        return
      end

      current_user.attach_payment_method!(payment_method_id)

      # Se veio de um redirecionamento da aba Disponíveis, volta para lá
      return_to = session.delete(:return_to_after_card)

      render json: {
        ok:           true,
        card_display: current_user.card_display,
        return_to:    return_to
      }
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # DELETE /client/profile/remove_payment_method
    def remove_payment_method
      current_user.detach_payment_method!
      redirect_to edit_client_profile_path, notice: "Cartão removido."
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
