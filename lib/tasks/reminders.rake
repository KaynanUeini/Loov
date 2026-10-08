namespace :reminders do
  desc "Envia o lembrete da véspera para os agendamentos de amanhã (todos os lotes)"
  task send: :environment do
    loop do
      result = AppointmentReminders.run!
      puts result.inspect
      break if result[:remaining].zero? || (result[:sent] + result[:failed]).zero?
    end
  end
end
