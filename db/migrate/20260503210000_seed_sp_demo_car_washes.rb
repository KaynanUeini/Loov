# Roda db/seeds/sp_demo.rb como uma migration. Render free não tem
# shell; migrations rodam automaticamente no deploy via build command
# (bundle exec rails db:migrate). Rails marca como executada em
# schema_migrations, então só roda uma vez. O próprio seed é idempotente
# (find_or_create_by) — re-executar não duplica nada.
class SeedSpDemoCarWashes < ActiveRecord::Migration[7.1]
  def up
    # Força reload do schema em memória — migrations anteriores nesta mesma
    # rodada de `db:migrate` adicionaram colunas (full_name/phone em users,
    # cep/logradouro/bairro em car_washes, etc.) que os models ainda não
    # enxergam sem isso, e o seed chama setters dessas colunas.
    [User, CarWash, OperatingHour, Service].each(&:reset_column_information)
    load Rails.root.join('db/seeds/sp_demo.rb').to_s
  end

  def down
    # No-op — manter os lava-rápidos demo mesmo se reverter a migration.
  end
end
