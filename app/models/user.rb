class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :appointments, dependent: :destroy
  has_many :car_washes, dependent: :destroy

  validates :role, presence: true, inclusion: { in: %w(client owner), message: "deve ser 'client' ou 'owner'" }
  validates :full_name, presence: { message: "é obrigatório" }, if: :client?
  validates :phone, presence: { message: "é obrigatório" }, if: :client?
  validates :cpf, format: { with: /\A\d{3}\.\d{3}\.\d{3}-\d{2}\z/, message: "formato inválido (ex: 000.000.000-00)" }, allow_blank: true

  def client?
    role == "client"
  end

  def owner?
    role == "owner"
  end

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
end
