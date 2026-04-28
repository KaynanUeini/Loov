module Owner
  # JSON-only API pra gestão de funcionários (atendentes) pelo dono no app.
  # Reusa o modelo AttendantInvitation já existente (que tem fluxo HTML).
  class AttendantsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner

    # GET /owner/attendants
    def index
      car_wash = current_user.car_washes.first
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found unless car_wash

      pending = car_wash.attendant_invitations.pending.order(created_at: :desc).map do |inv|
        {
          id:         inv.id,
          email:      inv.email,
          created_at: inv.created_at.iso8601
        }
      end

      attendants = car_wash.attendant_invitations.accepted
        .includes(:attendant).order(created_at: :desc)
        .map do |inv|
          u = inv.attendant
          {
            invitation_id: inv.id,
            user_id:       u&.id,
            email:         u&.email || inv.email,
            full_name:     u&.full_name,
            accepted_at:   inv.updated_at.iso8601
          }
        end

      render json: { attendants: attendants, pending: pending }
    end

    # POST /owner/attendants
    def create
      car_wash = current_user.car_washes.first
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found unless car_wash

      email = params[:email].to_s.strip.downcase
      return render json: { error: "Informe um e-mail válido." }, status: :unprocessable_entity if email.empty? || !email.include?("@")

      invitation = car_wash.attendant_invitations.build(
        inviter: current_user,
        email:   email,
        status:  "pending"
      )

      if invitation.save
        mail_error = nil
        begin
          Rails.logger.info("[AttendantsController#create] enviando convite pra #{invitation.email} (from=#{ApplicationMailer.default[:from]})")
          AttendantMailer.invitation(invitation).deliver_now
          Rails.logger.info("[AttendantsController#create] convite enviado com sucesso pra #{invitation.email}")
        rescue => e
          mail_error = "#{e.class}: #{e.message}"
          Rails.logger.error("[AttendantsController#create] mailer falhou pra #{invitation.email} — #{mail_error}\n#{e.backtrace&.first(5)&.join("\n")}")
        end
        render json: {
          ok:         true,
          id:         invitation.id,
          email:      invitation.email,
          mail_sent:  mail_error.nil?,
          mail_error: mail_error
        }
      else
        render json: { error: invitation.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    # DELETE /owner/attendants/invitations/:id — cancela convite pendente
    def destroy_invitation
      car_wash = current_user.car_washes.first
      invitation = car_wash&.attendant_invitations&.find_by(id: params[:id])
      return render json: { error: "Convite não encontrado." }, status: :not_found unless invitation
      invitation.destroy
      render json: { ok: true }
    end

    # DELETE /owner/attendants/:id — revoga acesso do funcionário (id = user_id)
    def destroy
      car_wash = current_user.car_washes.first
      invitation = car_wash&.attendant_invitations&.accepted&.find_by(attendant_id: params[:id])
      return render json: { error: "Funcionário não encontrado." }, status: :not_found unless invitation

      attendant = invitation.attendant
      ActiveRecord::Base.transaction do
        invitation.destroy
        # Volta o usuário pra client se ele só tinha acesso a esse car_wash.
        # (Se vier a ter acesso a vários no futuro, ajustar essa lógica.)
        attendant&.update_column(:role, "client")
      end
      render json: { ok: true }
    end

    private

    def ensure_owner
      render json: { error: "Acesso negado." }, status: :forbidden unless current_user&.owner?
    end
  end
end
