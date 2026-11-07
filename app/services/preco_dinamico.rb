# O preço de um serviço num horário, com a Hora Off e a Hora Pico.
#
# É o único lugar que decide preço: a lista de horários, o agendamento, o Last
# Minute, a home e o resumo do vale perguntam aqui. Nesta base, toda regra
# escrita em dois lugares acabou divergindo (o caminho que lista oferecia o que
# o caminho que cria recusava), por isso nenhum controller faz conta de preço.
#
# As regras, na ordem em que são aplicadas:
#   - Hora Off e Hora Pico desligadas: tudo pela tabela, o Last Minute também
#     (o ajuste em % por serviço foi aposentado; ver Service#preco_last_minute).
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
  # Quem agenda com mais de 6h de antecedência paga a tabela: o desconto é pra
  # quem preenche um horário que ia sobrar, não pra quem viria de qualquer
  # jeito. Janela curta de propósito: desconto que começa cedo ensina o cliente
  # a esperar, e aí ele deixa de agendar pelo preço cheio.
  ESCADA = [[90.minutes, 15], [3.hours, 10], [6.hours, 5]].freeze
  DESCONTO_LAST_MINUTE = 20
  EXTRA_CHUVA          = 5
  # Fatia da Loov no Last Minute (Appointment::COMMISSION_PCT): entra no piso
  # de quem vende por ali, porque sai do que o dono recebe.
  TAXA_LOOV_LAST_MINUTE = (Appointment::COMMISSION_PCT * 100).round

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
    min = car_wash.hora_off_enabled ? com_limites(tabela, [car_wash.hora_off_desconto_max.to_i, maior_desconto].min, true) : tabela
    max = car_wash.hora_pico_enabled ? (tabela * (100 + car_wash.hora_pico_pct) / 100.0).round.to_f : tabela
    { min: min, max: max }
  end

  # Tem horário com desconto da Hora Off daqui até o começo da escada (6h)? É
  # o que acende o selo e põe o lava-rápido no filtro Hora Off do cliente:
  # selo sem desconto pra achar seria promessa que o cliente não encontra.
  # Mesmas regras do preço: horário fraco, lava-rápido aberto e sem pausa, e
  # vaga pela duração inteira da lavagem mais curta que entra na Hora Off.
  def desconto_em_breve?
    return false unless car_wash.hora_off_enabled

    servico = car_wash.services.select { |s| aplica?(s) }.min_by { |s| s.duration.to_i }
    return false unless servico

    cada_horario_fraco { |slot| return true if car_wash.last_minute_cabe?(slot, servico) }
    false
  end

  # Até 45 min antes o cliente agenda pelo fluxo comum; dali em diante só pelo
  # Last Minute (a mesma trava de available_times e do agendamento).
  TRAVA_AGENDAMENTO = 45.minutes

  # A melhor oferta da Hora Off que o cliente ainda consegue agendar: o
  # horário fraco mais barato nas próximas 6h, com vaga pela duração inteira
  # do serviço. { preco:, tabela:, slot: } ou nil. É o que a página do
  # lava-rápido e a home mostram como "R$ 30 hoje às 22h": preço junto do
  # horário, pra não prometer o desconto em qualquer horário. No empate de
  # preço, o mais cedo.
  #
  # A vaga do Last Minute (os próximos 30 min) também concorre, com
  # last_minute: true: é onde o desconto é maior, e sem ela o cliente via
  # "R$ 30 às 22h" sem saber que às 20h saía por R$ 28. Só lavagem entra no
  # Last Minute, como em todo o resto.
  def melhor_oferta(service)
    return nil unless car_wash.hora_off_enabled && aplica?(service)

    melhor = nil
    if service.last_minute? && (lm = car_wash.last_minute_slot(agora, service)) && !fechado_no_dia?(lm.to_date)
      r = para(service, lm, last_minute: true)
      melhor = { preco: r.preco, tabela: r.tabela, slot: lm, last_minute: true } if r.tipo == "off"
    end
    cada_horario_fraco(a_partir_de: agora + TRAVA_AGENDAMENTO) do |slot|
      next unless car_wash.last_minute_cabe?(slot, service)
      r = para(service, slot)
      next unless r.tipo == "off"
      melhor = { preco: r.preco, tabela: r.tabela, slot: slot } if melhor.nil? || r.preco < melhor[:preco]
    end
    melhor
  end

  # Os horários (marcas de 30 min) de agora até o começo da escada que estão
  # fracos na grade, com o lava-rápido aberto, sem pausa e sem fechamento.
  # A vaga fica com quem pergunta: ela depende da duração do serviço.
  def cada_horario_fraco(a_partir_de: agora)
    passo  = CarWash::PASSO_LAST_MINUTE * 60
    limite = agora + ESCADA.map(&:first).max
    slot   = a_partir_de.beginning_of_day + ((a_partir_de.seconds_since_midnight / passo.to_f).ceil * passo).seconds
    while slot <= limite
      if car_wash.nivel_demanda(slot) == "fraco" && car_wash.aberto_em?(slot) &&
         !car_wash.pausado_para?(slot, agora) && !fechado_no_dia?(slot.to_date)
        yield slot
      end
      slot += passo.seconds
    end
  end

  # Abaixo disto a Hora Off não vende. É a conta da margem de contribuição:
  # num horário que ia ficar vazio, uma lavagem a mais só custa o variável
  # (produto, comissão, um pouco de água e luz), e o preço precisa cobrir isso,
  # as taxas sobre a venda e a margem mínima do dono:
  #
  #   piso = custo da lavagem ÷ (1 − taxas − margem)
  #
  # No Last Minute a fatia da Loov entra nas taxas. Sem o custo informado, nil:
  # vale só o teto de desconto.
  def piso(last_minute = false)
    @piso ||= {}
    return @piso[last_minute] if @piso.key?(last_minute)

    custo = car_wash.custo_lavagem.to_f
    return @piso[last_minute] = nil unless custo.positive?

    fatias = car_wash.taxas_venda_pct.to_i + car_wash.margem_minima.to_i +
             (last_minute ? TAXA_LOOV_LAST_MINUTE : 0)
    # Taxa e margem somando 90% ou mais não deixam o que dividir: o piso fica
    # dez vezes o custo, que já é "não dê desconto".
    @piso[last_minute] = (custo / (1 - [fatias, 90].min / 100.0)).ceil.to_f
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
    preco = com_limites(tabela, pct, last_minute)
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
  def com_limites(tabela, pct, last_minute)
    preco = (tabela * (100 - pct) / 100.0).round.to_f
    minimo = piso(last_minute)
    preco = [preco, minimo].max if minimo
    [preco, tabela].min
  end

  def fechado_no_dia?(dia)
    @fechado ||= {}
    return @fechado[dia] if @fechado.key?(dia)
    @fechado[dia] = car_wash.closed_on?(dia)
  end

  def chuva?(dia)
    return @chuva_por_dia[dia] if @chuva_por_dia.key?(dia)
    @chuva_por_dia[dia] = @chuva ? @chuva.call(dia) : PrevisaoChuva.provavel?(car_wash, dia)
  end
end
