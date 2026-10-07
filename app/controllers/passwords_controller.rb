# Reset de senha customizado.
# - POST /password/forgot (JSON): app pede reset → cria token + envia email
#   via Resend HTTPS API (Render bloqueia SMTP porta 587).
# - GET  /password/edit (HTML): página simples no estilo Loov pra usuário
#   digitar nova senha (acessada via link do email).
# - POST /password/update (HTML form): valida token + atualiza senha.
class PasswordsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:forgot, :update]
  skip_before_action :redirect_owner_without_car_wash, raise: false

  # Páginas standalone — não usar o layout principal (que tem navbar
  # autenticada e tema dark da landing). Cada view traz seu próprio
  # HTML self-contained.
  layout false

  # POST /password/forgot { email }
  def forgot
    email = params[:email].to_s.strip.downcase
    if email.empty? || !email.include?("@")
      return render json: { ok: false, error: "Informe um e-mail válido." }, status: :unprocessable_entity
    end

    user = User.find_by("LOWER(email) = ?", email)

    # Resposta sempre OK pra não revelar se o email existe ou não (anti-enum).
    # Mas só dispara o email de fato quando o user existe.
    if user
      raw_token = user.send(:set_reset_password_token)
      reset_url = build_reset_url(raw_token)
      send_reset_email(user, reset_url)
    end

    render json: {
      ok: true,
      message: "Se o e-mail estiver cadastrado, um link de redefinição foi enviado.",
    }
  end

  # GET /password/edit?reset_password_token=XXX
  def edit
    @reset_token = params[:reset_password_token].to_s
    @user = User.with_reset_password_token(@reset_token)
    if @user.nil? || !@user.reset_password_period_valid?
      @error = "Link inválido ou expirado. Solicite um novo no app."
      render :edit_invalid, status: :unprocessable_entity and return
    end
    render :edit
  end

  # POST /password/update
  def update
    token        = params[:reset_password_token].to_s
    password     = params[:password].to_s
    confirmation = params[:password_confirmation].to_s

    if password.length < 6
      @reset_token = token
      @error = "A senha precisa de ao menos 6 caracteres."
      @user = User.with_reset_password_token(token)
      render :edit, status: :unprocessable_entity and return
    end

    if password != confirmation
      @reset_token = token
      @error = "As senhas não coincidem."
      @user = User.with_reset_password_token(token)
      render :edit, status: :unprocessable_entity and return
    end

    user = User.reset_password_by_token(
      reset_password_token:  token,
      password:              password,
      password_confirmation: confirmation,
    )

    if user.errors.empty?
      render :update_success
    else
      @reset_token = token
      @error = user.errors.full_messages.join(", ")
      @user  = User.with_reset_password_token(token)
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def build_reset_url(raw_token)
    host     = ENV.fetch("APP_HOST", "loov-api.onrender.com")
    protocol = ENV.fetch("APP_PROTOCOL", "https")
    "#{protocol}://#{host}/password/edit?reset_password_token=#{raw_token}"
  end

  # Mesmo padrão do convite de atendente — Resend HTTPS API direto.
  def send_reset_email(user, reset_url)
    api_key = ENV["RESEND_API_KEY"].to_s.strip
    return Rails.logger.error("[Passwords] RESEND_API_KEY ausente") if api_key.empty?

    from_addr = ENV["MAILER_FROM"].presence || "Loov <onboarding@resend.dev>"
    payload = {
      from:    from_addr,
      to:      [user.email],
      subject: I18n.t("devise.mailer.reset_password_instructions.subject"),
      html:    reset_html(user, reset_url),
      text:    "Recebemos um pedido para redefinir a senha da sua conta na Loov.\n\nCrie a nova senha por este link (vale por #{Devise.reset_password_within.in_hours.to_i} horas):\n#{reset_url}\n\nNão foi você? Pode ignorar este e-mail — sua senha atual continua valendo.",
    }

    require "net/http"
    require "json"
    uri  = URI.parse("https://api.resend.com/emails")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.open_timeout = 8
    http.read_timeout = 12

    req = Net::HTTP::Post.new(uri.request_uri, {
      "Authorization" => "Bearer #{api_key}",
      "Content-Type"  => "application/json",
    })
    req.body = payload.to_json

    res = http.request(req)
    Rails.logger.info("[Passwords] Resend resp #{res.code} #{res.body.to_s[0, 200]}")
  rescue => e
    Rails.logger.error("[Passwords] envio falhou: #{e.class}: #{e.message}")
  end

  def reset_html(user, reset_url)
    render_to_string(
      template: "emails/reset_password",
      layout:   "mailer",
      formats:  [:html],
      locals:  {
        first_name: user.greeting_name,
        email:      user.email,
        url:        reset_url,
        hours:      Devise.reset_password_within.in_hours.to_i
      }
    )
  end
end
