module Owner
  # JSON-only API pra gestão de funcionários (atendentes) pelo dono no app.
  # Reusa o modelo AttendantInvitation já existente (que tem fluxo HTML).
  class AttendantsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner

    # GET /owner/attendants/diagnostic — lista car_washes do dono pra
    # debug em casos onde o user tem múltiplos (seed legado, etc).
    def diagnostic
      list = current_user.car_washes.order(:created_at).map do |cw|
        {
          id:                cw.id,
          name:              cw.name,
          created_at:        cw.created_at.iso8601,
          appointments_count: cw.appointments.count,
          attendants_active:  cw.attendant_invitations.where(status: "accepted").count,
          pending_invites:    cw.attendant_invitations.where(status: "pending").count,
        }
      end
      render json: {
        user_email:       current_user.email,
        car_washes_count: list.size,
        car_washes:       list,
        linked_car_wash_id: current_user.linked_car_wash&.id,
      }
    end

    # DELETE /owner/attendants/car_wash/:id — apaga um car_wash duplicado
    # (cleanup pra usuários que herdaram múltiplos via seed). Só permite
    # se houver mais de um car_wash no user (não deixa zerar).
    def destroy_car_wash
      car_wash = current_user.car_washes.find_by(id: params[:id])
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found unless car_wash
      if current_user.car_washes.count <= 1
        return render json: { error: "Você precisa manter ao menos um lava-rápido." }, status: :unprocessable_entity
      end
      name = car_wash.name
      car_wash.destroy!
      render json: { ok: true, deleted: name }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

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

      if email == current_user.email.to_s.downcase
        return render json: { error: "Você já é o dono — não dá pra se convidar como atendente." }, status: :unprocessable_entity
      end

      existing = User.find_by(email: email)
      if existing&.owner?
        return render json: { error: "Esse e-mail já é dono de um lava-rápido. Não dá pra convidar como atendente." }, status: :unprocessable_entity
      end

      invitation = car_wash.attendant_invitations.build(
        inviter: current_user,
        email:   email,
        status:  "pending"
      )

      if invitation.save
        mail_error = send_invitation_email_directly(invitation)
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

    # POST /owner/attendants/direct — cria atendente + convite aceito sem
    # passar por e-mail. Útil quando o dono está ao lado do funcionário e
    # define a senha na hora, ou pra contornar limites de sandbox de SMTP.
    def create_direct
      car_wash = current_user.car_washes.first
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found unless car_wash

      email     = params[:email].to_s.strip.downcase
      password  = params[:password].to_s
      full_name = params[:full_name].to_s.strip

      return render json: { error: "Informe um e-mail válido." }, status: :unprocessable_entity if email.empty? || !email.include?("@")
      return render json: { error: "Informe o nome do atendente." }, status: :unprocessable_entity if full_name.empty?
      return render json: { error: "Senha precisa de ao menos 6 caracteres." }, status: :unprocessable_entity if password.length < 6
      return render json: { error: "Esse e-mail já tem conta no Loov." }, status: :unprocessable_entity if User.exists?(email: email)

      begin
        ActiveRecord::Base.transaction do
          user = User.create!(
            email:     email,
            password:  password,
            role:      "attendant",
            full_name: full_name
          )
          car_wash.attendant_invitations.create!(
            inviter:   current_user,
            attendant: user,
            email:     email,
            status:    "accepted"
          )
        end
      rescue => e
        Rails.logger.error("[create_direct] #{e.class}: #{e.message}")
        return render json: { error: e.message }, status: :unprocessable_entity
      end

      render json: { ok: true, email: email }
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

    # Envia o convite chamando a HTTPS API do Resend direto (Net::HTTP).
    # Bypassa ActionMailer/SMTP — Render bloqueia porta 587. Retorna nil
    # em caso de sucesso, ou string com erro em caso de falha.
    def send_invitation_email_directly(invitation)
      api_key = ENV["RESEND_API_KEY"].to_s.strip
      return "RESEND_API_KEY ausente no ambiente" if api_key.empty?

      from_addr = ENV["MAILER_FROM"].presence || "Loov <onboarding@resend.dev>"
      app_host  = ENV.fetch("APP_HOST", "loov-api.onrender.com")
      protocol  = ENV.fetch("APP_PROTOCOL", "https")
      accept_url = "#{protocol}://#{app_host}/owner/attendant_invitations/#{invitation.token}/accept"
      car_wash_name = invitation.car_wash.name
      inviter_name  = invitation.inviter&.full_name.presence || "O dono"

      payload = {
        from:    from_addr,
        to:      [invitation.email],
        subject: "Convite: você foi adicionado ao #{car_wash_name} no Loov",
        html:    invitation_html(inviter_name, car_wash_name, accept_url),
        text:    "#{inviter_name} te convidou pra ser atendente do #{car_wash_name} no Loov.\n\nAceitar: #{accept_url}",
      }

      Rails.logger.info("[Resend API] POST emails to=#{invitation.email} from=#{from_addr}")
      uri = URI.parse("https://api.resend.com/emails")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl       = true
      http.open_timeout  = 8
      http.read_timeout  = 12

      req = Net::HTTP::Post.new(uri.request_uri, {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type"  => "application/json",
      })
      req.body = payload.to_json

      res = http.request(req)
      Rails.logger.info("[Resend API] response code=#{res.code} body=#{res.body.to_s[0, 400]}")

      if res.is_a?(Net::HTTPSuccess)
        nil
      else
        "Resend API #{res.code}: #{res.body.to_s[0, 200]}"
      end
    rescue => e
      msg = "#{e.class}: #{e.message}"
      Rails.logger.error("[Resend API] falha — #{msg}")
      msg
    end

    def invitation_html(inviter_name, car_wash_name, accept_url)
      <<~HTML
        <div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#28231c;background:#fafaf6;">
          <p style="font-family:'Courier New',monospace;font-size:11px;letter-spacing:1.5px;color:#ada699;text-transform:uppercase;margin:0 0 6px;">LOOV · CONVITE</p>
          <h1 style="font-size:22px;font-weight:700;letter-spacing:-0.3px;margin:0 0 18px;">Você foi convidado a ser atendente</h1>
          <p style="font-size:14px;line-height:22px;margin:0 0 12px;">
            <strong>#{inviter_name}</strong> te adicionou como atendente do <strong>#{car_wash_name}</strong> no Loov.
          </p>
          <p style="font-size:14px;line-height:22px;margin:0 0 24px;color:#575148;">
            Como atendente você gerencia agendamentos, registra avulsos e acompanha atendimentos — sem acesso à parte financeira.
          </p>
          <a href="#{accept_url}" style="display:inline-block;background:#dd7852;color:#fafaf6;text-decoration:none;padding:14px 22px;border-radius:100px;font-weight:600;letter-spacing:1px;font-size:13px;">ACEITAR CONVITE</a>
          <p style="font-size:12px;line-height:18px;margin:28px 0 0;color:#ada699;">
            Se recebeu por engano, é só ignorar.
          </p>
        </div>
      HTML
    end
  end
end
