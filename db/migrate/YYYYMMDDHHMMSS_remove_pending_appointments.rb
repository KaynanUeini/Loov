class RemovePendingAppointments < ActiveRecord::Migration[7.1]
  def up
    # Excluir todos os agendamentos com status 'pending'
    Appointment.where(status: 'pending').destroy_all
    puts "All pending appointments have been deleted."
  end

  def down
    # Não há necessidade de reverter, pois estamos excluindo dados
    # Se necessário, você pode adicionar uma lógica de recuperação aqui
  end
end
