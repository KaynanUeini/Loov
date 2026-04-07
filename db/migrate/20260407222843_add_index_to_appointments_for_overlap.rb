class AddIndexToAppointmentsForOverlap < ActiveRecord::Migration[7.1]
  def change
    # Índice composto para acelerar a query de overlap
    # car_wash_id + scheduled_at + status são sempre usados juntos na verificação
    add_index :appointments,
      [:car_wash_id, :scheduled_at, :status],
      name: "idx_appointments_overlap_check"
  end
end
