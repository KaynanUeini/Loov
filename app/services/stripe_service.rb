class StripeService
  def capture(payment_intent_id)
    Stripe::PaymentIntent.capture(payment_intent_id)
  end

  def refund(payment_intent_id, reason: "requested_by_customer")
    # Busca o payment intent para obter o charge
    intent = Stripe::PaymentIntent.retrieve(payment_intent_id)

    # Se já capturado, cria refund pelo charge
    if intent.latest_charge.present?
      Stripe::Refund.create(
        charge: intent.latest_charge,
        reason: reason
      )
    else
      # Se ainda não capturado (apenas autorizado), cancela o intent
      Stripe::PaymentIntent.cancel(payment_intent_id)
    end
  end

  def create_payment_intent(amount_cents:, currency: "brl", customer_id:, payment_method_id:, metadata: {})
    Stripe::PaymentIntent.create(
      amount:               amount_cents,
      currency:             currency,
      customer:             customer_id,
      payment_method:       payment_method_id,
      capture_method:       "manual",
      confirm:              true,
      metadata:             metadata
    )
  end
end
