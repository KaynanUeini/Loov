# Ordem do Last Minute: cada lava-rápido ganha uma nota de 0 a 100, soma dos
# fatores abaixo com seus pesos. É a ordem "Relevância" do site, do app e das
# prateleiras da home — todos recebem a lista já ordenada daqui.
#
# O cliente não vê nota nem explicação, só a ordem.
class RelevanciaLastMinute
  PESOS = { distancia: 30, preco: 25, avaliacao: 20, gostei: 15, servicos: 10 }.freeze

  # Até 1 km vale nota cheia; cai até zero no raio da busca do Last Minute.
  PERTO_KM = 1.0
  RAIO_KM  = 5.0

  # Média ponderada pelas avaliações: quem tem poucas fica perto da média
  # neutra, pra um 5,0 com uma avaliação não passar na frente de um 4,8 com 80.
  # Lava-rápido sem avaliação cai nela, sem prêmio nem castigo.
  MEDIA_NEUTRA = 4.5
  PESO_NEUTRO  = 5

  # Preço: perde a nota em proporção ao quanto passa do mais barato da lista;
  # 50% mais caro vale metade, o dobro vale zero.
  ACIMA_ZERA = 1.0

  # Variedade conta até 3 lavagens.
  TETO_VARIEDADE = 3

  # itens: as entradas montadas no DisponivelController (car_wash, services,
  # slots, min_price, distance_km). avaliacoes: { car_wash_id => { avg:, count: } }.
  # favoritos: Set de car_wash_id. usuario: pode ser nil (visitante).
  def initialize(itens, avaliacoes:, favoritos:, usuario: nil)
    @itens      = itens
    @avaliacoes = avaliacoes
    @favoritos  = favoritos
    @usuario    = usuario
  end

  # Mais relevante primeiro; no empate, o horário mais cedo.
  def ordenar
    @preco_min = @itens.map { |i| i[:min_price].to_f }.select(&:positive?).min
    @itens.sort_by { |i| [-nota(i), i[:slots].first, i[:min_price].to_f] }
  end

  def nota(item)
    fatores(item).sum { |fator, valor| PESOS[fator] * valor }.round(1)
  end

  # Cada fator de 0 a 1.
  def fatores(item)
    cw = item[:car_wash]
    {
      distancia: nota_distancia(item[:distance_km]),
      preco:     nota_preco(item[:min_price].to_f),
      avaliacao: nota_avaliacao(@avaliacoes[cw.id]),
      gostei:    @favoritos.include?(cw.id) ? 1.0 : 0.0,
      servicos:  nota_servicos(item[:services])
    }
  end

  private

  # Sem localização do cliente, a distância não separa ninguém.
  def nota_distancia(km)
    return 0.5 if km.nil?
    return 1.0 if km <= PERTO_KM
    (1 - (km - PERTO_KM) / (RAIO_KM - PERTO_KM)).clamp(0.0, 1.0)
  end

  # Menor preço de lavagem comparado com o mais barato da lista. Ele já vem com
  # a Hora Off ou a Hora Pico do horário, então as duas entram por aqui. Por
  # porcentagem e não do mais barato ao mais caro: nessa escala o mais caro
  # zerava a nota mesmo custando só R$ 5 a mais.
  def nota_preco(preco)
    base = @preco_min || preco
    return 1.0 unless base.to_f.positive? && preco.positive?
    (1 - (preco / base - 1) / ACIMA_ZERA).clamp(0.0, 1.0)
  end

  # 5,0 vale 1; 3,0 ou menos vale 0.
  def nota_avaliacao(r)
    media = r ? r[:avg].to_f : 0.0
    total = r ? r[:count].to_i : 0
    ponderada = (media * total + MEDIA_NEUTRA * PESO_NEUTRO) / (total + PESO_NEUTRO)
    ((ponderada - 3.0) / 2.0).clamp(0.0, 1.0)
  end

  # Com histórico: tem o tipo de lavagem que o cliente costuma fazer? Sem
  # histórico: quantas lavagens o lava-rápido oferece agora.
  def nota_servicos(servicos)
    if (preferido = lavagem_preferida)
      servicos.any? { |s| self.class.tipo(s.title) == preferido } ? 1.0 : 0.0
    else
      [servicos.size, TETO_VARIEDADE].min.to_f / TETO_VARIEDADE
    end
  end

  # Tipo de lavagem mais frequente entre as que o cliente fez (ou tem marcada).
  def lavagem_preferida
    return @preferida if defined?(@preferida)
    @preferida = if @usuario
      Service.last_minute
             .joins(:appointments)
             .where(appointments: { user_id: @usuario.id, status: %w[attended confirmed] })
             .pluck(:title)
             .map { |t| self.class.tipo(t) }
             .tally.max_by { |_, n| n }&.first
    end
  end

  # "Lavagem Completa" e "lavagem completa" são o mesmo tipo, em qualquer loja.
  def self.tipo(titulo)
    I18n.transliterate(titulo.to_s).downcase.squish
  end
end
