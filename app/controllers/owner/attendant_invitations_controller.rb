module Owner
  class AttendantInvitationsController < ApplicationController
    # accept/do_accept são públicos — convidado ainda nem tem conta criada,
    # então não pode passar pelo authenticate_user!.
    before_action :authenticate_user!, except: [:accept, :do_accept]
    before_action :ensure_owner,       except: [:accept, :do_accept]

    def index
      @car_wash    = current_user.car_washes.first
      @invitations = @car_wash.attendant_invitations.order(created_at: :desc)
    end

    def create
      @car_wash   = current_user.car_washes.first
      @invitation = @car_wash.attendant_invitations.build(
        inviter: current_user,
        email:   params[:email].to_s.strip.downcase,
        status:  "pending"
      )

      if @invitation.save
        AttendantMailer.invitation(@invitation).deliver_now rescue nil
        redirect_to owner_attendant_invitations_path, notice: "Convite enviado para #{@invitation.email}."
      else
        @invitations = @car_wash.attendant_invitations.order(created_at: :desc)
        flash.now[:alert] = @invitation.errors.full_messages.join(", ")
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      @car_wash   = current_user.car_washes.first
      @invitation = @car_wash.attendant_invitations.find(params[:id])
      @invitation.destroy
      redirect_to owner_attendant_invitations_path, notice: "Convite removido."
    end

    # GET /owner/attendant_invitations/:token/accept
    def accept
      @invitation = AttendantInvitation.find_by(token: params[:token], status: "pending")
      redirect_to root_path, alert: "Convite inválido ou já utilizado." unless @invitation
    end

    # POST /owner/attendant_invitations/:token/accept
    def do_accept
      Rails.logger.info("[do_accept] hit token=#{params[:token].to_s[0,8]}... ip=#{request.remote_ip}")
      @invitation = AttendantInvitation.find_by(token: params[:token], status: "pending")
      unless @invitation
        Rails.logger.warn("[do_accept] convite inválido/já usado — token=#{params[:token].to_s[0,8]}...")
        redirect_to root_path, alert: "Convite inválido ou já utilizado." and return
      end

      user = User.find_by(email: @invitation.email)

      if user
        # Bloqueia auto-convite (dono tentou se convidar). Sem isso o
        # accept! antigo mudava role pra attendant e quebrava o acesso.
        if user.owner?
          Rails.logger.warn("[do_accept] tentativa de aceitar convite por dono user_id=#{user.id} email=#{user.email}")
          redirect_to root_path, alert: "Esse e-mail já é dono — não dá pra aceitar como atendente." and return
        end
        @invitation.accept!(user)
        Rails.logger.info("[do_accept] aceito por user existente id=#{user.id}")
        sign_in(user)
        redirect_to root_path, notice: "Convite aceito! Bem-vindo ao #{@invitation.car_wash.name}."
      else
        # Cria conta de atendente
        user = User.new(
          email:                 @invitation.email,
          password:              params[:password],
          password_confirmation: params[:password_confirmation],
          role:                  "attendant",
          full_name:             params[:full_name]
        )
        if user.save
          @invitation.accept!(user)
          Rails.logger.info("[do_accept] criada nova conta atendente id=#{user.id}")
          sign_in(user)
          redirect_to root_path, notice: "Conta criada! Bem-vindo ao #{@invitation.car_wash.name}."
        else
          Rails.logger.warn("[do_accept] falha ao criar user — #{user.errors.full_messages.join(", ")}")
          flash.now[:alert] = user.errors.full_messages.join(", ")
          render :accept, status: :unprocessable_entity
        end
      end
    rescue => e
      Rails.logger.error("[do_accept] exceção #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      redirect_to root_path, alert: "Erro inesperado. Tenta de novo ou avisa o dono."
    end

    private

    def ensure_owner
      redirect_to root_path, alert: "Acesso não autorizado." unless current_user&.owner?
    end
  end
end
