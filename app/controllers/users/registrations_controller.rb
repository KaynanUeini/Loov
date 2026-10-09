class Users::RegistrationsController < Devise::RegistrationsController
  respond_to :json, :html

  skip_before_action :verify_authenticity_token, if: :json_request?

  # Papéis que alguém pode escolher ao se cadastrar. Atendente vem do convite
  # do dono (AttendantInvitation) e admin só pelo painel — aceitar o `role`
  # do formulário como viesse deixava qualquer um se cadastrar como admin.
  SELF_SERVICE_ROLES = %w[client owner].freeze

  # Página "Conta" do cliente (porte da ClientProfileScreen do app). Também no
  # update: se trocar a senha falhar, o Devise renderiza o edit de novo.
  before_action :load_client_account, only: [:edit, :update]

  protected

  # Depois de trocar e-mail/senha, fica na própria Conta com o aviso, em vez
  # de cair na home sem saber se deu certo.
  def after_update_path_for(resource)
    edit_user_registration_path
  end

  def sign_up_params
    super.tap do |p|
      p[:role] = "client" unless SELF_SERVICE_ROLES.include?(p[:role])
    end
  end

  private

  def load_client_account
    return unless current_user&.client?
    u = current_user
    @account = {
      email:          u.email,
      full_name:      u.full_name,
      phone:          u.phone,
      cpf:            u.cpf,
      vehicle_model:  u.vehicle_model,
      vehicle_plate:  u.vehicle_plate,
      has_card:       u.stripe_payment_method_id.present?,
      card_display:   u.card_display,
      attended_count: u.appointments.where(status: "attended").count,
      favorites_count: u.favorite_car_washes.count
    }
  end

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
