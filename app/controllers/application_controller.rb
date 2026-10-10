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

  # Assinatura única por visita pros <script> da página. Só tem efeito nas
  # páginas com política rígida (strict_csp!): lá, script sem essa assinatura
  # não roda — nem um injetado por um invasor.
  helper_method :csp_nonce
  def csp_nonce
    @csp_nonce ||= SecureRandom.base64(18)
  end

  helper_method :strict_csp?
  def strict_csp?
    !!@strict_csp
  end

  protected

  # Páginas que mexem com cartão: só scripts nossos (com a assinatura desta
  # visita) e do Stripe; nada de CDN; e a página não pode ser exibida dentro
  # de outro site (clickjacking). Recomendações de CSP do próprio Stripe.
  def strict_csp!
    @strict_csp = true
    response.headers["Content-Security-Policy"] = [
      "default-src 'self'",
      "script-src 'self' 'nonce-#{csp_nonce}' https://js.stripe.com https://*.js.stripe.com",
      "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdn.jsdelivr.net",
      "font-src 'self' https://fonts.gstatic.com https://cdn.jsdelivr.net",
      "img-src 'self' data: https:",
      # fonts.googleapis.com: o Stripe busca daqui a fonte dos campos do cartão.
      "connect-src 'self' https://api.stripe.com https://fonts.googleapis.com",
      "frame-src https://js.stripe.com https://*.js.stripe.com https://hooks.stripe.com",
      "frame-ancestors 'none'",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'"
    ].join("; ")
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Cache-Control"] = "no-store"
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:role, :full_name, :phone, :cpf, :vehicle_model])
  end

  # Cliente de API (app) não pode receber redirect pra tela HTML: o wizard de
  # onboarding mora dentro do próprio app, e um 302 aqui chegaria no fetch como
  # HTML no lugar do JSON esperado.
  def api_request?
    request.format.json? || request.headers['Authorization'].present?
  end

  def redirect_owner_without_car_wash
    return unless user_signed_in?
    return unless current_user.owner?
    return if current_user.car_washes.any?
    return if api_request?
    return if controller_name == 'onboarding'
    return if controller_name == 'sessions'
    return if controller_name == 'registrations'
    redirect_to owner_onboarding_path
  end

  # Retorna o lava-rápido do usuário logado (owner ou attendant)
  def current_car_wash
    @current_car_wash ||= current_user&.linked_car_wash
  end
  helper_method :current_car_wash
end
