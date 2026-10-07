class Users::RegistrationsController < Devise::RegistrationsController
  respond_to :json, :html

  skip_before_action :verify_authenticity_token, if: :json_request?

  # Papéis que alguém pode escolher ao se cadastrar. Atendente vem do convite
  # do dono (AttendantInvitation) e admin só pelo painel — aceitar o `role`
  # do formulário como viesse deixava qualquer um se cadastrar como admin.
  SELF_SERVICE_ROLES = %w[client owner].freeze

  protected

  def sign_up_params
    super.tap do |p|
      p[:role] = "client" unless SELF_SERVICE_ROLES.include?(p[:role])
    end
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
      render json: {
        error:  resource.errors.full_messages.join(', '),
        errors: resource.errors.as_json
      }, status: :unprocessable_entity
    end
  end
end
