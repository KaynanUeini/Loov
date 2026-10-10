module Client
  class ProfilesController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_client

    def show
      if request.format.json?
        render json: profile_payload
      else
        redirect_to edit_client_profile_path
      end
    end

    def edit
      # A página de perfil do site agora é a Conta (/users/edit, porte da tela
      # do app). Aqui fica só o cartão — aberto por "Pagamentos" na Conta ou
      # pelo checkout do Disponível (add_card).
      if request.format.html? && !payment_tab?
        redirect_to edit_user_registration_path(request.query_parameters.slice("latitude", "longitude")) and return
      end

      if request.format.html?
        strict_csp!
        backfill_card_details
        # Vindo da reserva do Last Minute: depois de salvar o cartão, volta
        # pra ela. Só caminho interno, nunca outro site.
        rt = params[:return_to].to_s
        session[:return_to_after_card] = rt if rt.start_with?("/") && !rt.start_with?("//")
      end

      # Na página do cartão o SetupIntent é sempre preparado: serve pra
      # cadastrar o primeiro cartão e também pra trocar o atual.
      if request.format.html? || current_user.stripe_customer_id.present? || params[:add_card]
        customer = current_user.stripe_customer!
        @setup_intent = Stripe::SetupIntent.create(
          customer:             customer.id,
          payment_method_types: ["card"],
          usage:                "off_session"
        )
        @setup_client_secret = @setup_intent.client_secret
      end

      respond_to do |format|
        format.html
        format.json do
          render json: profile_payload.merge(
            setup_intent_id:     @setup_intent&.id,
            setup_client_secret: @setup_client_secret,
            stripe_customer_id:  current_user.stripe_customer_id,
            publishable_key:     stripe_publishable_key
          )
        end
      end
    rescue Stripe::StripeError => e
      Rails.logger.error("ProfilesController#edit Stripe error: #{e.message}")
      respond_to do |format|
        format.html { @setup_client_secret = nil; render :edit }
        format.json { render json: profile_payload.merge(stripe_error: e.message) }
      end
    end

    def update
      if current_user.update(profile_params)
        respond_to do |format|
          format.html { redirect_to edit_user_registration_path, notice: "Perfil atualizado com sucesso." }
          format.json { render json: { ok: true, profile: profile_payload } }
        end
      else
        respond_to do |format|
          format.html do
            flash.now[:errors] = current_user.errors.full_messages
            render :edit, status: :unprocessable_entity
          end
          format.json do
            render json: { ok: false, error: current_user.errors.full_messages.join(", ") },
                   status: :unprocessable_entity
          end
        end
      end
    end

    # POST /client/profile/attach_payment_method
    # Aceita payment_method_id direto OU setup_intent_id (mobile PaymentSheet)
    def attach_payment_method
      payment_method_id = params[:payment_method_id].presence

      if payment_method_id.blank? && params[:setup_intent_id].present?
        si = Stripe::SetupIntent.retrieve(params[:setup_intent_id])
        payment_method_id = si.payment_method
      end

      if payment_method_id.blank?
        render json: { error: "payment_method_id é obrigatório" }, status: :unprocessable_entity
        return
      end

      had_card = current_user.has_payment_method?
      current_user.attach_payment_method!(payment_method_id)
      notify_card_change(had_card ? :replaced : :added, current_user.card_display)

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
      removed = current_user.card_display
      current_user.detach_payment_method!
      notify_card_change(:removed, removed) if removed
      respond_to do |format|
        format.html { redirect_to edit_client_profile_path(tab: "pagamento"), notice: "Cartão removido." }
        format.json { render json: { ok: true } }
      end
    end

    private

    # Cartões salvos antes de guardarmos nome e validade: busca uma vez no
    # Stripe pra tela mostrar os dados reais. Falhou? A tela usa o nome da conta.
    def backfill_card_details
      u = current_user
      return unless u.stripe_payment_method_id.present? && u.stripe_card_exp_month.nil?
      pm = Stripe::PaymentMethod.retrieve(u.stripe_payment_method_id)
      u.update_columns(
        stripe_card_holder:    pm.billing_details&.name.presence,
        stripe_card_exp_month: pm.card&.exp_month,
        stripe_card_exp_year:  pm.card&.exp_year
      )
    rescue Stripe::StripeError => e
      Rails.logger.warn("[Pagamentos] backfill do cartão falhou: #{e.message}")
    end

    # E-mail de segurança. Falha no envio não pode desfazer a mudança do cartão.
    def notify_card_change(action, card_display)
      AccountMailer.card_changed(current_user, action, card_display).deliver_now
    rescue => e
      Rails.logger.error("[Pagamentos] aviso de cartão (#{action}) não enviado: #{e.message}")
    end

    def payment_tab?
      params[:add_card].present? || params[:tab] == "pagamento"
    end
    helper_method :payment_tab?

    def ensure_client
      return if current_user&.client?
      if request.format.json?
        render json: { error: "Acesso negado." }, status: :forbidden
      else
        redirect_to root_path
      end
    end

    def profile_params
      params.require(:user).permit(:full_name, :phone, :cpf, :vehicle_model, :vehicle_plate)
    end

    def profile_payload
      {
        id:            current_user.id,
        email:         current_user.email,
        full_name:     current_user.full_name,
        phone:         current_user.phone,
        cpf:           current_user.cpf,
        vehicle_model: current_user.vehicle_model,
        vehicle_plate: current_user.vehicle_plate,
        has_card:      current_user.stripe_payment_method_id.present?,
        card_display:  current_user.card_display,
        card_brand:    current_user.stripe_card_brand,
        card_last4:    current_user.stripe_card_last4,
        card_holder:   current_user.stripe_card_holder,
        card_exp_month: current_user.stripe_card_exp_month,
        card_exp_year:  current_user.stripe_card_exp_year
      }
    end

    # Mesma fonte que o site usa (ENV); credentials fica de reserva.
    def stripe_publishable_key
      ENV["STRIPE_PUBLISHABLE_KEY"].presence || Rails.application.credentials.dig(:stripe, :publishable_key)
    end
  end
end
