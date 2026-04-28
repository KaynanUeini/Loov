class ApplicationMailer < ActionMailer::Base
  # Configurável via ENV — Resend exige domínio verificado.
  default from: ENV.fetch("MAILER_FROM", "Loov <onboarding@resend.dev>")
  layout "mailer"
end
