class Users::RegistrationsController < Devise::RegistrationsController
  respond_to :json, :html

  skip_before_action :verify_authenticity_token, if: :json_request?

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
