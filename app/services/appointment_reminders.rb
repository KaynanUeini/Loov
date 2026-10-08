# Lembrete da véspera: e-mail pro cliente com agendamento confirmado amanhã.
#
# Disparado uma vez por dia de fora (GitHub Actions → POST /internal/reminders),
# porque no Render free não há worker nem cron e o servidor dorme sem acesso:
# um job agendado aqui dentro se perderia. Processa em lotes (o rack-timeout
# corta a requisição em 15s); quem chama repete enquanto `remaining` > 0.
class AppointmentReminders
  BATCH = 20

  # Quem agendou há pouco acabou de receber a confirmação — um lembrete
  # horas depois seria repetição, não lembrete.
  RECENT_BOOKING = 12.hours

  def self.run!(batch: BATCH)
    new.run!(batch: batch)
  end

  def run!(batch: BATCH)
    sent = 0
    failed = 0

    due.limit(batch).each do |appointment|
      # Marca antes de enviar: se o envio falhar, não fica tentando de novo a
      # cada chamada (e-mail duplicado é pior que um lembrete a menos).
      appointment.update_column(:reminder_sent_at, Time.current)
      begin
        AppointmentMailer.reminder(appointment).deliver_now
        sent += 1
      rescue => e
        failed += 1
        Rails.logger.error("[Reminders] appt ##{appointment.id}: #{e.class}: #{e.message}")
      end
    end

    { date: tomorrow.iso8601, sent: sent, failed: failed, remaining: due.count }
  end

  def due
    Appointment
      .where(status: "confirmed", reminder_sent_at: nil, walk_in: false)
      .where.not(user_id: nil)
      .where(scheduled_at: tomorrow.beginning_of_day..tomorrow.end_of_day)
      .where("appointments.created_at < ?", RECENT_BOOKING.ago)
      .includes(:user, :car_wash, :service)
      .order(:scheduled_at)
  end

  private

  def tomorrow
    Time.zone.today + 1 # Time.zone = America/Sao_Paulo (config/application.rb)
  end
end
