class AttendantMailer < ApplicationMailer
  def invitation(invitation)
    @invitation = invitation
    @car_wash   = invitation.car_wash
    @inviter    = invitation.inviter
    @accept_url = url_for(
      controller: "owner/attendant_invitations",
      action:     "accept",
      token:      invitation.token,
      only_path:  false,
      host:       ENV.fetch("APP_HOST", "loov-api.onrender.com"),
      protocol:   ENV.fetch("APP_PROTOCOL", "https")
    )
    mail(
      to:      invitation.email,
      subject: "Convite: você foi adicionado ao #{@car_wash.name} no Loov"
    )
  end
end
