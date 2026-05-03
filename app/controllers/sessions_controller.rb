class SessionsController < Devise::SessionsController
  respond_to :json, :html

  skip_before_action :verify_authenticity_token, if: :json_request?

  def after_sign_in_path_for(resource)
    flash.clear
    root_path
  end

  # Override do create pra validar credenciais EXPLICITAMENTE pra requests
  # JSON. Antes confiava 100% no Warden, mas qualquer estratégia adicional
  # poderia teoricamente autenticar sem checar a senha. Aqui buscamos o
  # user pelo email e validamos a senha via valid_password? antes de
  # chamar super (que dispara o Warden e gera o JWT).
  def create
    if json_request?
      email    = params.dig(:user, :email).to_s.strip.downcase
      password = params.dig(:user, :password).to_s

      if email.empty? || password.empty?
        Rails.logger.warn("[Sessions] login bloqueado — email ou senha em branco (email=#{email.inspect})")
        render json: { error: 'Informe e-mail e senha.' }, status: :unprocessable_entity and return
      end

      user = User.find_by("LOWER(email) = ?", email)

      if user.nil?
        Rails.logger.warn("[Sessions] login falhou — user não encontrado (email=#{email.inspect})")
        render json: { error: 'E-mail ou senha inválidos.' }, status: :unauthorized and return
      end

      unless user.valid_password?(password)
        Rails.logger.warn("[Sessions] login falhou — senha incorreta (user_id=#{user.id} email=#{email.inspect})")
        render json: { error: 'E-mail ou senha inválidos.' }, status: :unauthorized and return
      end

      Rails.logger.info("[Sessions] login OK (user_id=#{user.id} email=#{email.inspect} role=#{user.role})")
    end

    super
  end

  private

  def json_request?
    request.format.json?
  end

  def respond_with(resource, _opts = {})
    return super unless json_request?

    if resource.persisted?
      render json: {
        token: request.env['warden-jwt_auth.token'],
        role:  resource.role,
        email: resource.email,
        name:  resource.display_name,
        id:    resource.id
      }, status: :ok
    else
      render json: { error: 'E-mail ou senha inválidos.' }, status: :unprocessable_entity
    end
  end

  def respond_to_on_destroy
    return super unless json_request?
    render json: { message: 'Logout realizado.' }, status: :ok
  end
end
