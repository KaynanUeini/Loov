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
      subject: "Redefinição de senha — Loov",
      html:    reset_html(user, reset_url),
      text:    "Você pediu pra redefinir sua senha no Loov.\n\nAcesse: #{reset_url}\n\nSe não foi você, ignore este email.",
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
    name = user.full_name.presence || user.email.split("@").first.capitalize
    <<~HTML
      <div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#28231c;background:#fafaf6;">
        <p style="font-family:'Courier New',monospace;font-size:11px;letter-spacing:1.5px;color:#ada699;text-transform:uppercase;margin:0 0 6px;">LOOV · REDEFINIR SENHA</p>
        <h1 style="font-size:22px;font-weight:700;letter-spacing:-0.3px;margin:0 0 18px;">Olá, #{name}</h1>
        <p style="font-size:14px;line-height:22px;margin:0 0 12px;">
          Recebemos um pedido pra redefinir a senha da sua conta no Loov.
        </p>
        <p style="font-size:14px;line-height:22px;margin:0 0 24px;color:#575148;">
          Toque no botão abaixo pra criar uma nova senha. O link expira em 6 horas.
        </p>
        <a href="#{reset_url}" style="display:inline-block;background:#dd7852;color:#fafaf6;text-decoration:none;padding:14px 22px;border-radius:100px;font-weight:600;letter-spacing:1px;font-size:13px;">REDEFINIR SENHA</a>
        <p style="font-size:12px;line-height:18px;margin:28px 0 0;color:#ada699;">
          Se não foi você que pediu, é só ignorar este email — sua senha continua a mesma.
        </p>
      </div>
    HTML
  end
end
