# Avisos de segurança da conta. Toda mudança no cartão gera um e-mail: se não
# foi o cliente, ele descobre na hora — a senha pode ter vazado e alguém pode
# estar tentando usar a conta (e o cartão salvo) pra reservar no Last Minute.
class AccountMailer < ApplicationMailer
  ACTIONS = {
    added:    { subject: "Cartão adicionado à sua conta Loov", eyebrow: "Cartão adicionado", title: "Você adicionou um cartão." },
    replaced: { subject: "Cartão da sua conta Loov foi trocado", eyebrow: "Cartão trocado",     title: "Você trocou o cartão da conta." },
    removed:  { subject: "Cartão removido da sua conta Loov",   eyebrow: "Cartão removido",     title: "Você removeu o cartão da conta." }
  }.freeze

  def card_changed(user, action, card_display)
    @user   = user
    @action = ACTIONS.fetch(action.to_sym)
    @kind   = action.to_sym
    @card   = card_display.presence || "Cartão"
    @when   = Time.current.in_time_zone("America/Sao_Paulo").strftime("%d/%m/%Y às %H:%M")
    @url    = "#{ENV.fetch('APP_PROTOCOL', 'https')}://#{ENV.fetch('APP_HOST', 'loov-api.onrender.com')}/client/profile/edit?tab=pagamento"
    mail(to: user.email, subject: @action[:subject])
  end
end
