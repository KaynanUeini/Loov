# O preço de um serviço num horário, com a Hora Off e a Hora Pico.
#
# É o único lugar que decide preço: a lista de horários, o agendamento, o Last
# Minute, a home e o resumo do vale perguntam aqui. Nesta base, toda regra
# escrita em dois lugares acabou divergindo (o caminho que lista oferecia o que
# o caminho que cria recusava), por isso nenhum controller faz conta de preço.
#
# As regras, na ordem em que são aplicadas:
#   - Hora Off e Hora Pico desligadas: tudo como antes. O agendamento comum sai
#     pela tabela e o Last Minute pelo ajuste em % do serviço.
#   - Só entram lavagens (ou o serviço que o dono incluiu). O resto, tabela.
#   - Horário fraco, Hora Off ligada: desconto que cresce conforme o horário
#     chega perto ainda livre (ESCADA), maior no Last Minute, mais um extra com
#     chuva prevista. Nunca passa do teto do dono nem desce do piso de margem.
#   - Horário forte, Hora Pico ligada: acréscimo, só no Last Minute.
#   - O resto, e o Last Minute de horário normal: tabela.
#
# Preço em reais inteiros, como o Last Minute já era (R$ 38, não R$ 38,25).
class PrecoDinamico
  Resultado = Struct.new(:preco, :tabela, :tipo, :pct, keyword_init: true) do
    # Hora Off ou Hora Pico mudaram o preço.
    def dinamico?
      tipo.present?
    end
  end

  # [antecedência máxima, % de desconto] — o primeiro degrau que couber vale.
  # Quem agenda com mais de 12h de antecedência paga a tabela: o desconto é pra
  # quem preenche um horário que ia sobrar, não pra quem viria de qualquer jeito.
  ESCADA = [[2.hours, 15], [6.hours, 10], [12.hours, 5]].freeze
  DESCONTO_LAST_MINUTE = 20
  EXTRA_CHUVA          = 5

  attr_reader :car_wash, :agora

  # `agora` é o momento da reserva: o check-in recalcula com o created_at do
  # agendamento, pra trocar de serviço sem mudar a regra que valeu na hora.
  # `chuva` responde "vai chover neste dia?"; os testes passam um lambda.
  def initialize(car_wash, agora: Time.current, chuva: nil)
    @car_wash = car_wash
    @agora    = agora
    @chuva    = chuva
    @chuva_por_dia = {}
  end

  def para(service, slot, last_minute: false)
    tabela = service.price.to_f
    return legado(service, tabela, last_minute) unless car_wash.preco_dinamico_ativo?
    return pela_tabela(tabela) unless aplica?(service)

    case car_wash.nivel_demanda(slot)
    when "fraco"
      car_wash.hora_off_enabled ? hora_off(tabela, slot, last_minute) : pela_tabela(tabela)
    when "forte"
      car_wash.hora_pico_enabled && last_minute ? hora_pico(tabela) : pela_tabela(tabela)
    else
      pela_tabela(tabela)
    end
  end

  # O menor e o maior preço que este serviço pode ter, pro painel do dono.
  def faixa(service)
    tabela = service.price.to_f
    return { min: tabela, max: tabela } unless aplica?(service)

    maior_desconto = DESCONTO_LAST_MINUTE + (car_wash.hora_off_chuva_enabled ? EXTRA_CHUVA : 0)
    min = car_wash.hora_off_enabled ? com_limites(tabela, [car_wash.hora_off_desconto_max.to_i, maior_desconto].min) : tabela
    max = car_wash.hora_pico_enabled ? (tabela * (100 + car_wash.hora_pico_pct) / 100.0).round.to_f : tabela
    { min: min, max: max }
  end

  # Abaixo disto a Hora Off não vende: o custo médio de uma lavagem mais a
  # margem mínima do dono. nil sem custos lançados.
  def piso
    return @piso if defined?(@piso)
    custo  = car_wash.custo_por_lavagem(agora)
    margem = car_wash.margem_minima.to_i.clamp(0, 90)
    @piso  = custo && (custo[:valor] / (1 - margem / 100.0)).ceil.to_f
  end

  def aplica?(service)
    service.hora_off_incluido.nil? ? service.last_minute? : service.hora_off_incluido
  end

  private

  def legado(service, tabela, last_minute)
    preco = last_minute ? service.preco_last_minute : tabela
    Resultado.new(preco: preco, tabela: tabela, tipo: nil, pct: 0)
  end

  def pela_tabela(tabela)
    Resultado.new(preco: tabela, tabela: tabela, tipo: nil, pct: 0)
  end

  def hora_off(tabela, slot, last_minute)
    pct = last_minute ? DESCONTO_LAST_MINUTE : degrau(slot)
    return pela_tabela(tabela) if pct.zero?

    pct  += EXTRA_CHUVA if car_wash.hora_off_chuva_enabled && chuva?(slot.to_date)
    pct   = [pct, car_wash.hora_off_desconto_max.to_i].min
    preco = com_limites(tabela, pct)
    return pela_tabela(tabela) if preco >= tabela

    Resultado.new(preco: preco, tabela: tabela, tipo: "off", pct: pct)
  end

  def hora_pico(tabela)
    pct = car_wash.hora_pico_pct.to_i
    return pela_tabela(tabela) unless pct.positive?

    Resultado.new(preco: (tabela * (100 + pct) / 100.0).round.to_f, tabela: tabela, tipo: "pico", pct: pct)
  end

  def degrau(slot)
    falta = slot - agora
    return 0 if falta.negative?
    ESCADA.each { |limite, pct| return pct if falta <= limite }
    0
  end

  # Tabela menos o desconto, arredondado, nunca abaixo do piso nem acima da
  # tabela.
  def com_limites(tabela, pct)
    preco = (tabela * (100 - pct) / 100.0).round.to_f
    preco = [preco, piso].max if piso
    [preco, tabela].min
  end

  def chuva?(dia)
    return @chuva_por_dia[dia] if @chuva_por_dia.key?(dia)
    @chuva_por_dia[dia] = @chuva ? @chuva.call(dia) : PrevisaoChuva.provavel?(car_wash, dia)
  end
end
