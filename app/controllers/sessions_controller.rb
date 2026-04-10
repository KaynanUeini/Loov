class SessionsController < Devise::SessionsController
  respond_to :json, :html

  skip_before_action :verify_authenticity_token, if: :json_request?

  def after_sign_in_path_for(resource)
    flash.clear
    root_path
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
