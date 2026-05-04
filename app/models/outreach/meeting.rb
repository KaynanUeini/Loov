module Outreach
  class Meeting < ApplicationRecord
    self.table_name = 'outreach_meetings'

    belongs_to :lead, class_name: 'Outreach::Lead', foreign_key: :lead_id

    KINDS    = %w[presencial video telefone].freeze
    STATUSES = %w[agendado realizado cancelado no_show].freeze

    validates :scheduled_at, presence: true
    validates :kind,         inclusion: { in: KINDS }
    validates :status,       inclusion: { in: STATUSES }

    scope :upcoming, -> { where('scheduled_at >= ?', Time.current).order(:scheduled_at) }
    scope :past,     -> { where('scheduled_at <  ?', Time.current).order(scheduled_at: :desc) }
  end
end
