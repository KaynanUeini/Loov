class AttendantMailer < ApplicationMailer
  def invitation(invitation)
    @invitation   = invitation
    @car_wash     = invitation.car_wash
    # Nome de quem convidou, quando dá pra confiar nele. Sem nome, o texto
    # fala do lava-rápido — "Não conhece O dono?" não é frase.
    @inviter_name = invitation.inviter&.greeting_name
    @accept_url   = "#{ENV.fetch('APP_PROTOCOL', 'https')}://#{ENV.fetch('APP_HOST', 'loov-api.onrender.com')}" \
                    "/owner/attendant_invitations/#{invitation.token}/accept"
    subject = @inviter_name ? "#{@inviter_name} convidou você para a equipe · #{@car_wash.name}" : "Convite para a equipe · #{@car_wash.name}"
    mail(to: invitation.email, subject: subject)
  end
end
