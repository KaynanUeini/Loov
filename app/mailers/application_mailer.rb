class ApplicationMailer < ActionMailer::Base
  # Configurável via ENV — Resend exige domínio verificado pra enviar
  # pra terceiros. Sem domínio, usa onboarding@resend.dev (sandbox: só
  # entrega pro e-mail dono da conta Resend). presence trata vazio.
  default from: (ENV["MAILER_FROM"].presence || "Loov <onboarding@resend.dev>")
  layout "mailer"
end
