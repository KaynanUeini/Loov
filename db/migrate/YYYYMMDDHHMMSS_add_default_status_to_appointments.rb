class AddDefaultStatusToAppointments < ActiveRecord::Migration[7.1]
  def change
    # Adicionar valor padrão 'pending' à coluna status
    change_column_default :appointments, :status, from: nil, to: 'pending'

    # Atualizar registros existentes para definir status como 'pending' se for nil
    reversible do |dir|
      dir.up do
        Appointment.where(status: nil).update_all(status: 'pending')
      end
    end
  end
end
