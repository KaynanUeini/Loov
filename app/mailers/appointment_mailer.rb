class AppointmentMailer < ApplicationMailer
  def confirmation(appointment)
    @appointment = appointment
    @user        = appointment.user
    @car_wash    = appointment.car_wash
    @service     = appointment.service
    mail(to: @user.email, subject: "Agendamento confirmado — #{appointment.car_wash.name}")
  end

  def reminder(appointment)
    @appointment = appointment
    @user        = appointment.user
    mail(to: @user.email, subject: "Lembrete: seu agendamento é amanhã — #{appointment.car_wash.name}")
  end

  def closure_cancellation(appointment, closure)
    @appointment = appointment
    @closure     = closure
    @user        = appointment.user
    mail(to: @user.email, subject: "Agendamento cancelado — #{appointment.car_wash.name} estará fechado")
  end

  def owner_cancellation(appointment)
    @appointment = appointment
    @user        = appointment.user
    mail(to: @user.email, subject: "Agendamento cancelado — #{appointment.car_wash.name}")
  end
end
