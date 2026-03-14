class ApplicationController < ActionController::Base
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :redirect_owner_without_car_wash

  def after_sign_in_path_for(resource)
    if resource.owner? && resource.car_washes.empty?
      owner_onboarding_path
    else
      root_path
    end
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:role, :full_name, :phone])
  end

  def redirect_owner_without_car_wash
    return unless user_signed_in?
    return unless current_user.owner?
    return if current_user.car_washes.any?
    return if controller_name == 'onboarding'
    return if controller_name == 'sessions'
    return if controller_name == 'registrations'
    redirect_to owner_onboarding_path
  end
end
