# Limpa phone = '' (string vazia) pra NULL em outreach_leads. O índice
# único parcial WHERE phone IS NOT NULL não excluía empty strings,
# então duas linhas com phone = '' batiam o constraint.
class NullifyBlankPhonesInOutreachLeads < ActiveRecord::Migration[7.1]
  def up
    return unless table_exists?(:outreach_leads)
    execute <<~SQL
      UPDATE outreach_leads
      SET phone = NULL
      WHERE phone IS NOT NULL AND TRIM(phone) = ''
    SQL
  end

  def down
    # No-op
  end
end
