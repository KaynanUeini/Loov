class RemovePendenteAppointments < ActiveRecord::Migration[7.1]
  def up
    # Excluir todos os agendaments com status 'pendente'
    Appointment.where(status: 'pendente').destroy_all
    puts "All appointments with status 'pendente' have been deleted."
  end

  def down
    # Não há necessidade de reverter, pois estamos excluindo dados
    # Se necessário, você pode adicionar uma lógica de recuperação aqui
  end
end
