class Users::SessionsController < Devise::SessionsController
  respond_to :json

  private

  def respond_with(resource, _opts = {})
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
    render json: { message: 'Logout realizado.' }, status: :ok
  end
end
