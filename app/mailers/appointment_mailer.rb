class AppointmentMailer < ApplicationMailer
  # Todo e-mail de agendamento recebe o mesmo conjunto de variáveis. Antes
  # cada método setava umas e o template usava outras: closure_cancellation
  # e reminder quebravam com @car_wash nil e o cliente não era avisado.
  #
  # Agendamento de balcão não tem cliente com e-mail — sem `mail`, o
  # deliver_now não envia nada (em vez de estourar com to: nil).

  def confirmation(appointment)
    return unless prepare(appointment)
    mail(to: @user.email, subject: "Agendamento confirmado · #{@car_wash.name}")
  end

  def reminder(appointment)
    return unless prepare(appointment)
    mail(to: @user.email, subject: "Amanhã às #{@appointment.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%H:%M")} · #{@car_wash.name}")
  end

  def closure_cancellation(appointment, closure)
    return unless prepare(appointment)
    @closure = closure
    mail(to: @user.email, subject: "Seu agendamento foi cancelado · #{@car_wash.name}")
  end

  def owner_cancellation(appointment)
    return unless prepare(appointment)
    mail(to: @user.email, subject: "Seu agendamento foi cancelado · #{@car_wash.name}")
  end

  private

  def prepare(appointment)
    @appointment = appointment
    @user        = appointment.user
    @car_wash    = appointment.car_wash
    @service     = appointment.service
    @user&.email.present?
  end
end
