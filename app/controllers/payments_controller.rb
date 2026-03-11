class PaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_appointment

  def new
    if @appointment.payment.present?
      redirect_to car_wash_path(@appointment.car_wash), alert: "Pagamento já realizado para este agendamento."
      return
    end
    # A página de checkout já é renderizada por AppointmentsController#new,
    # então não precisamos de uma view aqui. Redirecionamos para evitar erros.
    redirect_to car_wash_appointment_path(car_wash_id: @appointment.car_wash_id, service_id: @appointment.service_id, scheduled_at_date: @appointment.scheduled_at.strftime("%Y-%m-%d"), scheduled_at_time: @appointment.scheduled_at.strftime("%H:%M")), alert: "Use a página de checkout para realizar o pagamento."
  end

  def create
    if @appointment.payment.present?
      redirect_to car_wash_path(@appointment.car_wash), alert: "Pagamento já realizado para este agendamento."
      return
    end

    customer = Stripe::Customer.create(
      email: current_user.email,
      source: params[:stripe_token]
    )

    charge = Stripe::Charge.create(
      customer: customer.id,
      amount: (@appointment.service.price * 100).to_i,
      description: "Pagamento para agendamento ##{@appointment.id}",
      currency: 'brl'
    )

    @payment = Payment.create!(
      appointment: @appointment,
      stripe_charge_id: charge.id,
      amount: @appointment.service.price
    )

    @appointment.update(status: 'confirmed')
    redirect_to appointments_path, notice: "Pagamento realizado com sucesso!"
  rescue Stripe::CardError => e
    redirect_to car_wash_appointment_path(car_wash_id: @appointment.car_wash_id, service_id: @appointment.service_id, scheduled_at_date: @appointment.scheduled_at.strftime("%Y-%m-%d"), scheduled_at_time: @appointment.scheduled_at.strftime("%H:%M")), alert: e.message
  end

  def success
    redirect_to appointments_path, notice: "Pagamento realizado com sucesso!"
  end

  def cancel
    redirect_to appointments_path, alert: "Pagamento cancelado."
  end

  private

  def set_appointment
    @appointment = Appointment.find(params[:appointment_id])
  end
end
