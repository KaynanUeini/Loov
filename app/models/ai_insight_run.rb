class AiInsightRun < ApplicationRecord
  belongs_to :ai_insight, optional: true
  belongs_to :car_wash

  STATUSES = %w[success parse_fallback api_error].freeze

  scope :recent,    -> { order(created_at: :desc) }
  scope :successes, -> { where(status: "success") }
  scope :failures,  -> { where.not(status: "success") }

  def success?         = status == "success"
  def parse_fallback?  = status == "parse_fallback"
  def api_error?       = status == "api_error"
end
