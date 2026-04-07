# config/initializers/filter_parameter_logging.rb
# Filtra dados sensíveis dos logs — NUNCA devem aparecer em log/production.log

Rails.application.config.filter_parameters += [
  # Autenticação
  :password,
  :password_confirmation,
  :current_password,
  :token,
  :secret,
  :api_key,

  # PII — Personally Identifiable Information
  :email,
  :phone,
  :cpf,
  :full_name,
  :name,
  :address,

  # Pagamentos
  :stripe_payment_intent_id,
  :stripe_customer_id,
  :payment_method_id,
  :card_number,
  :cvv,
  :expiry,

  # Outros
  :authenticity_token,
  :session,
  :cookie
]
