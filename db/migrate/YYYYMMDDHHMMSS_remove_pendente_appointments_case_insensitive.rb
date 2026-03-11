class RemovePendenteAppointmentsCaseInsensitive < ActiveRecord::Migration[7.1]
  def up
    # Excluir todos os agendaments com status 'pendente' ou 'Pendente' (case-insensitive)
    Appointment.where("LOWER(status) IN (?)", ['pendente']).destroy_all
    puts "All appointments with status 'pendente' or 'Pendente' (case-insensitive) have been deleted."
  end

  def down
    # Não há necessidade de reverter, pois estamos excluindo dados
    # Se necessário, você pode adicionar uma lógica de recuperação aqui
  end
end
