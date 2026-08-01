class DeleteItalyWashTestAppointment < ActiveRecord::Migration[7.1]
  # Remove o agendamento de teste que o dono criou pra validar o fluxo Last
  # Minute ponta a ponta. Ficou "confirmed" na agenda de produção e contaria
  # como atendimento real em relatório.
  #
  # Nem o dono nem o cliente conseguem tirá-lo pelo app: owner/checkins#cancel
  # recusa agendamentos do tipo disponivel, e disponivel#cancel só aceita
  # pending_acceptance. Render free não tem shell, então sobra migration —
  # mesmo caminho dos seeds e da limpeza de lava-rápidos deste projeto.
  ID = 19

  # O id sozinho não basta: em outro banco ele aponta pra outro registro. Só
  # apaga se TUDO bater — se divergir, não faz nada e diz por quê.
  ESPERADO = {
    car_wash:         "Italy Wash",
    client:           "Ramiro",
    appointment_type: "disponivel"
  }.freeze

  def up
    ap = Appointment.find_by(id: ID)

    if ap.nil?
      say "Nenhum agendamento ##{ID} neste banco — nada a fazer."
      return
    end

    real = {
      car_wash:         ap.car_wash&.name,
      client:           ap.user&.full_name,
      appointment_type: ap.appointment_type
    }

    if real != ESPERADO
      say "Agendamento ##{ID} não confere com o alvo — nada a fazer."
      say "esperado: #{ESPERADO.inspect}", true
      say "real:     #{real.inspect}", true
      return
    end

    say "Removendo ##{ap.id} — #{real[:client]} @ #{real[:car_wash]}, " \
        "#{ap.status}, agendado #{ap.scheduled_at}"
    ap.destroy!
    say "Removido."
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Remoção de dados não tem volta."
  end
end
