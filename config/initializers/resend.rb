# Configura a gem resend pra entrega via HTTPS API (porta 443).
# Necessário porque Render (e muitos PaaS) bloqueiam SMTP outbound nas
# portas 587/465 — Net::OpenTimeout dá timeout antes do socket abrir.

require "resend"
require "resend/mailer"

Resend.api_key = ENV["RESEND_API_KEY"] if ENV["RESEND_API_KEY"].present?

# Registra :resend como delivery method do ActionMailer.
ActionMailer::Base.add_delivery_method :resend, Resend::Mailer
