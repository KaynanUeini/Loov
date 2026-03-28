class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :appointments,          dependent: :destroy
  has_many :car_washes,            dependent: :destroy
  has_many :support_tickets,       dependent: :destroy
  has_many :sent_invitations,      class_name: "AttendantInvitation", foreign_key: :inviter_id,   dependent: :destroy
  has_many :attendant_invitations, class_name: "AttendantInvitation", foreign_key: :attendant_id, dependent: :nullify

  validates :role, presence: true, inclusion: { in: %w(client owner attendant admin), message: "deve ser 'client', 'owner', 'attendant' ou 'admin'" }
  validates :full_name, presence: { message: "é obrigatório" }, if: :client?
  validates :phone,     presence: { message: "é obrigatório" }, if: :client?
  validates :cpf, format: { with: /\A\d{3}\.\d{3}\.\d{3}-\d{2}\z/, message: "formato inválido (ex: 000.000.000-00)" }, allow_blank: true

  def client?;    role == "client";    end
  def owner?;     role == "owner";     end
  def attendant?; role == "attendant"; end
  def admin?;     role == "admin";     end

  def display_name
    full_name.presence || email.split("@").first.capitalize
  end

  def initials
    if full_name.present?
      full_name.split(" ").first(2).map { |n| n[0] }.join.upcase
    else
      email[0].upcase
    end
  end

  def profile_complete?
    full_name.present? && phone.present?
  end

  def linked_car_wash
    if owner?
      car_washes.first
    elsif attendant?
      accepted = attendant_invitations.accepted.includes(:car_wash).first
      accepted&.car_wash
    end
  end

  # ── STRIPE ────────────────────────────────────────────────────────────────

  def has_payment_method?
    stripe_payment_method_id.present?
  end

  # Garante que o cliente tem um Customer no Stripe, criando se necessário
  def stripe_customer!
    if stripe_customer_id.present?
      Stripe::Customer.retrieve(stripe_customer_id)
    else
      customer = Stripe::Customer.create(
        email:    email,
        name:     display_name,
        metadata: { loov_user_id: id }
      )
      update_column(:stripe_customer_id, customer.id)
      customer
    end
  rescue Stripe::StripeError => e
    Rails.logger.error("User#stripe_customer! error: #{e.message}")
    raise
  end

  # Salva um PaymentMethod no cliente e o define como padrão
  def attach_payment_method!(payment_method_id)
    customer = stripe_customer!
    pm = Stripe::PaymentMethod.attach(payment_method_id, { customer: customer.id })
    Stripe::Customer.update(customer.id, { invoice_settings: { default_payment_method: pm.id } })
    update!(
      stripe_payment_method_id: pm.id,
      stripe_card_last4:        pm.card&.last4,
      stripe_card_brand:        pm.card&.brand&.capitalize
    )
    pm
  rescue Stripe::StripeError => e
    Rails.logger.error("User#attach_payment_method! error: #{e.message}")
    raise
  end

  # Remove o cartão salvo
  def detach_payment_method!
    return unless stripe_payment_method_id.present?
    Stripe::PaymentMethod.detach(stripe_payment_method_id) rescue nil
    update!(stripe_payment_method_id: nil, stripe_card_last4: nil, stripe_card_brand: nil)
  end

  # Card display string ex: "Visa •••• 4242"
  def card_display
    return nil unless has_payment_method?
    "#{stripe_card_brand} •••• #{stripe_card_last4}"
  end
end
