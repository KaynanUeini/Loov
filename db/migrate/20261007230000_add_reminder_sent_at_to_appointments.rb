# Marca quando o lembrete da véspera saiu. É o que torna o envio idempotente:
# se o disparo diário rodar duas vezes (retry do GitHub Actions, alguém
# rodando na mão), ninguém recebe o lembrete repetido.
class AddReminderSentAtToAppointments < ActiveRecord::Migration[7.1]
  def change
    add_column :appointments, :reminder_sent_at, :datetime
  end
end
