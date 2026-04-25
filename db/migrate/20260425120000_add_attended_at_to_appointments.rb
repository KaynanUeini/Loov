class AddAttendedAtToAppointments < ActiveRecord::Migration[7.1]
  def change
    # Quando o atendimento foi de fato finalizado pelo dono/funcionário
    # (clique em "Finalizado"). Para walk-ins, fica nulo e o cálculo de
    # capacidade usa o fallback scheduled_at + duration.
    add_column :appointments, :attended_at, :datetime
    add_index  :appointments, :attended_at
  end
end
