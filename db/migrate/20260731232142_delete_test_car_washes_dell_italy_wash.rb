class DeleteTestCarWashesDellItalyWash < ActiveRecord::Migration[7.1]
  # Remove os lava-rápidos de teste "Dell" e "Italy Wash" a pedido do dono, que
  # vai recriá-los. Render free não tem shell, então operação pontual em dados
  # roda como migration — mesmo caminho já usado pelos seeds deste projeto.
  #
  # Destrutivo e irreversível: dependent: :destroy leva junto serviços,
  # horários, agendamentos, avaliações e programa de fidelidade de cada um.
  # Aceitável aqui por serem cadastros de teste; por isso o limite abaixo.
  #
  # Casamento por "contém", não por nome exato: o cadastro real diverge do que
  # foi pedido de boca ("Italy Wash" está gravado só como "Italy"), e nome
  # exato faria a migration rodar, não achar nada e passar por bem-sucedida.
  # A abrangência extra é contida pela trava de MAX_ESPERADO abaixo.
  TERMOS = ["%dell%", "%italy%"].freeze
  MAX_ESPERADO = 10

  # Seis tabelas apontam pra car_washes sem `dependent: :destroy` no model, e o
  # banco tem foreign key: `destroy!` sozinho estoura ForeignKeyViolation (foi o
  # que aconteceu com support_tickets). Limpar aqui, e não no model, é de
  # propósito — pôr `dependent: :destroy` em support_tickets faria remover um
  # lava-rápido apagar histórico de suporte no app inteiro, que é outra decisão.
  #
  # Ordem importa: ai_insight_runs referencia ai_insights.
  # support_tickets vai por destroy_all pra levar junto suas mensagens.
  DEPENDENTES = %w[
    ai_insight_runs
    ai_insights
    attendant_activities
    favorite_car_washes
    owner_messages
  ].freeze

  def up
    alvos = CarWash.where(
      TERMOS.map { "LOWER(name) LIKE ?" }.join(" OR "), *TERMOS
    )
    total = alvos.count

    if total.zero?
      say "Nenhum lava-rápido casou com #{TERMOS.inspect} — nada a fazer."
      return
    end

    # Trava de segurança: se casar muito mais do que o esperado, algo está
    # errado no critério e é melhor abortar do que apagar em massa.
    if total > MAX_ESPERADO
      raise "Abortado: #{total} lava-rápidos casaram com #{TERMOS.inspect}, acima do limite de #{MAX_ESPERADO}."
    end

    alvos.each do |cw|
      say "Removendo ##{cw.id} #{cw.name.inspect} (user_id=#{cw.user_id}) — " \
          "#{cw.appointments.count} agendamento(s), #{cw.services.count} serviço(s)"

      say_with_time "limpando dependentes sem cascade de ##{cw.id}" do
        tickets = SupportTicket.where(car_wash_id: cw.id)
        say "support_tickets: #{tickets.count}", true
        tickets.destroy_all

        DEPENDENTES.each do |tabela|
          apagados = connection.delete(
            "DELETE FROM #{connection.quote_table_name(tabela)} " \
            "WHERE car_wash_id = #{connection.quote(cw.id)}"
          )
          say "#{tabela}: #{apagados}", true if apagados > 0
        end
      end

      cw.destroy!
    end

    say "#{total} lava-rápido(s) removido(s)."
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Remoção de dados não tem volta."
  end
end
