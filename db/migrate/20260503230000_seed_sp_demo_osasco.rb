# Re-roda db/seeds/sp_demo.rb pra pegar os bairros de Osasco
# adicionados depois que a migration original (20260503210000) já tinha
# sido marcada como executada. O seed é idempotente — usa
# find_or_create_by, então os 60 lava-rápidos de SP que já existem não
# são duplicados; só os 15 novos de Osasco são criados.
class SeedSpDemoOsasco < ActiveRecord::Migration[7.1]
  def up
    load Rails.root.join('db/seeds/sp_demo.rb').to_s
  end

  def down
    # No-op
  end
end
