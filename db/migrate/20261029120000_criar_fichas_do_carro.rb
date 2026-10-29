# Ficha do carro: o registro do estado do veículo na entrada, que protege o
# lava-rápido do "vocês riscaram meu carro". Pelo CDC o lava-rápido responde
# pelo dano mesmo sem culpa (art. 14) e o cliente tem 5 anos pra processar
# (art. 27); a única defesa é provar que a avaria já existia.
#
#   car_washes.vehicle_check_enabled    pede a ficha ao tocar em Compareceu
#   car_washes.vehicle_check_mode       choose (atendente escolhe) | photos | sketch
#   car_washes.vehicle_check_skippable  o atendente pode pular a ficha
#
# vehicle_checks guarda uma ficha por atendimento, que não muda depois de
# salva (ver VehicleCheck):
#   mode     photos | sketch | skipped (pular também fica registrado: o dono vê)
#   photos   [{ "label" => "front", "key" => "fichas/…jpg" }] no Cloudflare R2
#   marks    [{ "n" => 1, "x" => 0.5, "y" => 0.1, "kind" => "risco", "area" => "…" }]
#            x/y de 0 a 1 sobre o desenho visto de cima, frente em cima
#   recorded_at  hora do servidor, nunca a do celular
#   expires_at   recorded_at + 5 anos, quando a ficha pode ser apagada
class CriarFichasDoCarro < ActiveRecord::Migration[7.1]
  def change
    add_column :car_washes, :vehicle_check_enabled,   :boolean, default: false,    null: false
    add_column :car_washes, :vehicle_check_mode,      :string,  default: "choose", null: false
    add_column :car_washes, :vehicle_check_skippable, :boolean, default: true,     null: false

    create_table :vehicle_checks do |t|
      t.references :car_wash,    null: false, foreign_key: true
      t.references :appointment, null: false, foreign_key: true, index: { unique: true }
      t.references :recorded_by, null: false, foreign_key: { to_table: :users }
      t.string   :plate
      t.string   :vehicle_model
      t.string   :mode,        null: false
      t.jsonb    :photos,      null: false, default: []
      t.jsonb    :marks,       null: false, default: []
      t.text     :notes
      t.datetime :recorded_at, null: false
      t.datetime :expires_at,  null: false
      t.timestamps
    end
    add_index :vehicle_checks, [:car_wash_id, :plate]
    add_index :vehicle_checks, :expires_at
  end
end
