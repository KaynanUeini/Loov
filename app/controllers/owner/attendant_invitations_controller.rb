module Owner
  class AttendantInvitationsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_owner, except: [:accept, :do_accept]

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
      @invitation = AttendantInvitation.find_by(token: params[:token], status: "pending")
      unless @invitation
        redirect_to root_path, alert: "Convite inválido ou já utilizado." and return
      end

      user = User.find_by(email: @invitation.email)

      if user
        @invitation.accept!(user)
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
          sign_in(user)
          redirect_to root_path, notice: "Conta criada! Bem-vindo ao #{@invitation.car_wash.name}."
        else
          flash.now[:alert] = user.errors.full_messages.join(", ")
          render :accept, status: :unprocessable_entity
        end
      end
    end

    private

    def ensure_owner
      redirect_to root_path, alert: "Acesso não autorizado." unless current_user&.owner?
    end
  end
end
