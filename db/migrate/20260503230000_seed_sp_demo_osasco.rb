# Re-roda db/seeds/sp_demo.rb pra pegar os bairros de Osasco
# adicionados depois que a migration original (20260503210000) já tinha
# sido marcada como executada. O seed é idempotente — usa
# find_or_create_by, então os 60 lava-rápidos de SP que já existem não
# são duplicados; só os 15 novos de Osasco são criados.
class SeedSpDemoOsasco < ActiveRecord::Migration[7.1]
  def up
    # Mesmo tratamento da migration original 20260503210000 — força reload
    # do schema em memória pra que os setters de colunas adicionadas em
    # migrations anteriores funcionem.
    [User, CarWash, OperatingHour, Service].each(&:reset_column_information)
    load Rails.root.join('db/seeds/sp_demo.rb').to_s
  end

  def down
    # No-op
  end
end
