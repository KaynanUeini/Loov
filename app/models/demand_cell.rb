# Um quadrado da grade da Hora Off e da Hora Pico: o dia da semana e a faixa de
# hora que o dono marcou como fraco, normal ou forte. Sem linha gravada vale o
# padrão da Loov (DemandCell.nivel_padrao), então lava-rápido novo já nasce com
# uma grade razoável e só grava o que mudar.
class DemandCell < ApplicationRecord
  belongs_to :car_wash

  FAIXAS = %w[manha almoco tarde noite].freeze
  NIVEIS = %w[fraco normal forte].freeze

  # Onde cada faixa começa, em horas. A do slot é decidida pelo horário de
  # início: uma lavagem das 11:30 às 12:30 é da manhã.
  INICIO_FAIXA = { "manha" => 0, "almoco" => 12, "tarde" => 14, "noite" => 18 }.freeze
  FIM_FAIXA    = { "manha" => 12, "almoco" => 14, "tarde" => 18, "noite" => 24 }.freeze

  validates :dia,   inclusion: { in: 0..6 }
  validates :faixa, inclusion: { in: FAIXAS }
  validates :nivel, inclusion: { in: NIVEIS }

  def self.faixa_de(slot)
    h = slot.hour
    return "manha"  if h < 12
    return "almoco" if h < 14
    return "tarde"  if h < 18
    "noite"
  end

  # Padrão da Loov até o dono (ou, na etapa seguinte, o histórico) dizer outra
  # coisa. Segunda a quinta de manhã e no almoço é onde o lava-rápido de bairro
  # costuma ficar parado; sábado e sexta à tarde, onde costuma lotar. Domingo e
  # noite ficam normais: muito lava-rápido nem abre, e quem abre varia demais.
  def self.nivel_padrao(dia, faixa)
    return "fraco" if (1..4).cover?(dia) && %w[manha almoco].include?(faixa)
    return "forte" if dia == 6 && faixa != "noite"
    return "forte" if dia == 5 && faixa == "tarde"
    "normal"
  end
end
