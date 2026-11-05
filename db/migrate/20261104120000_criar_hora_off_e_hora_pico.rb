# Hora Off e Hora Pico: o preço segue a procura de cada horário.
#
# Horário fraco que ainda está livre perto da hora fica mais barato (Hora Off);
# horário forte que ainda tem vaga no Last Minute fica mais caro (Hora Pico).
# Quem decide se um horário é fraco, normal ou forte é a grade do lava-rápido:
# começa no padrão da Loov e o dono ajusta. As duas funções nascem desligadas,
# então este deploy não muda o preço de ninguém.
class CriarHoraOffEHoraPico < ActiveRecord::Migration[7.1]
  def change
    change_table :car_washes, bulk: true do |t|
      t.boolean :hora_off_enabled,       default: false, null: false
      t.boolean :hora_pico_enabled,      default: false, null: false
      t.boolean :hora_off_chuva_enabled, default: true,  null: false
      # Teto do desconto da Hora Off, em % da tabela, somando escada e chuva.
      t.integer :hora_off_desconto_max,  default: 25,    null: false
      # Margem que a Hora Off nunca fura, sobre o custo médio por lavagem.
      t.integer :margem_minima,          default: 35,    null: false
      t.integer :hora_pico_pct,          default: 15,    null: false
    end

    # nil = segue a categoria (lavagem entra, o resto fica na tabela).
    add_column :services, :hora_off_incluido, :boolean

    # A grade: uma linha por dia da semana e faixa de hora que o dono marcou.
    # Sem linha, vale o padrão da Loov (HoraOff::Grade).
    create_table :demand_cells do |t|
      t.references :car_wash, null: false, foreign_key: true
      t.integer :dia,   null: false # 0 = domingo, como Date#wday
      t.string  :faixa, null: false # manha | almoco | tarde | noite
      t.string  :nivel, null: false # fraco | normal | forte
      t.timestamps
    end
    add_index :demand_cells, [:car_wash_id, :dia, :faixa], unique: true

    # Foto semanal da grade. É o que a Loov previu; o que aconteceu já está nos
    # agendamentos. Comparar os dois é como o aprendizado vai ser medido.
    create_table :demand_snapshots do |t|
      t.references :car_wash, null: false, foreign_key: true
      t.date  :semana, null: false # segunda-feira da semana
      t.jsonb :grade,  null: false, default: {}
      t.timestamps
    end
    add_index :demand_snapshots, [:car_wash_id, :semana], unique: true

    # O preço cobrado continua em price_override (o vale e o ajuste do dono no
    # check-in mexem nele). Estes três guardam o que a Hora Off ou a Hora Pico
    # decidiram na reserva: o relatório separa o que cada uma vendeu, e
    # preco_ajustado? não confunde preço dinâmico com ajuste manual.
    change_table :appointments, bulk: true do |t|
      t.decimal :preco_tabela,   precision: 10, scale: 2
      t.decimal :preco_dinamico, precision: 10, scale: 2
      t.string  :preco_tipo # off | pico
    end
  end
end
