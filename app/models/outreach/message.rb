module Outreach
  class Message < ApplicationRecord
    self.table_name = 'outreach_messages'

    belongs_to :lead, class_name: 'Outreach::Lead', foreign_key: :lead_id

    CHANNELS = %w[whatsapp email phone manual].freeze

    validates :body,    presence: true
    validates :channel, inclusion: { in: CHANNELS }
  end
end
