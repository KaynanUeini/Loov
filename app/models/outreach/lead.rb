module Outreach
  class Lead < ApplicationRecord
    self.table_name = 'outreach_leads'

    has_many :messages, class_name: 'Outreach::Message', foreign_key: :lead_id, dependent: :destroy
    has_many :meetings, class_name: 'Outreach::Meeting', foreign_key: :lead_id, dependent: :destroy

    STATUSES = %w[novo enviado respondeu agendado convertido recusado].freeze

    validates :name,   presence: true
    validates :status, inclusion: { in: STATUSES }

    # Normaliza phone — string em branco vira NULL pra o índice único
    # parcial (WHERE phone IS NOT NULL) não tropeçar em "".
    before_validation :nullify_blank_phone

    scope :by_status, ->(s) { where(status: s) }

    private

    def nullify_blank_phone
      self.phone = nil if phone.blank?
    end

    public

    def whatsapp_link(message_body = nil)
      return nil if phone.blank?
      digits = phone.gsub(/\D/, '')
      digits = "55#{digits}" unless digits.start_with?('55')
      base = "https://wa.me/#{digits}"
      message_body.present? ? "#{base}?text=#{ERB::Util.url_encode(message_body)}" : base
    end

    def display_phone
      return nil if phone.blank?
      digits = phone.gsub(/\D/, '')
      digits = digits.last(11) if digits.length > 11
      case digits.length
      when 11 then "(#{digits[0..1]}) #{digits[2..6]}-#{digits[7..10]}"
      when 10 then "(#{digits[0..1]}) #{digits[2..5]}-#{digits[6..9]}"
      else digits
      end
    end
  end
end
