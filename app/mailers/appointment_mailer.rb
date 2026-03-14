class AppointmentMailer < ApplicationMailer
 default from: "Loov <onboarding@resend.dev>"

  def confirmation(appointment)
    @appointment = appointment
    @user = appointment.user
    @car_wash = appointment.car_wash
    @service = appointment.service
    mail(to: @user.email, subject: "✅ Agendamento confirmado — #{@car_wash.name}")
  end

  def reminder(appointment)
    @appointment = appointment
    @user = appointment.user
    @car_wash = appointment.car_wash
    @service = appointment.service
    mail(to: @user.email, subject: "⏰ Lembrete: seu agendamento é amanhã — #{@car_wash.name}")
  end
end

