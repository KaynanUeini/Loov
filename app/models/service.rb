class Service < ApplicationRecord
  CATEGORIES = [
    "Lavagem",
    "Polimento",
    "Higienização",
    "Cristalização",
    "Vitrificação",
    "Enceramento",
    "Hidratação de Couro",
    "Limpeza de Motor",
    "Revitalização de Plásticos",
    "Polimento de Faróis",
    "Impermeabilização",
    "Oxi-sanitização",
    "Outros"
  ].freeze

  GROUPS = {
    "Lavagem"   => ["Lavagem"],
    "Estética"  => ["Polimento", "Cristalização", "Vitrificação", "Enceramento"],
    "Higiene"   => ["Higienização", "Hidratação de Couro", "Impermeabilização", "Oxi-sanitização"],
    "Especiais" => ["Limpeza de Motor", "Revitalização de Plásticos", "Polimento de Faróis"],
    "Outros"    => ["Outros"]
  }.freeze

  # ── LAST MINUTE ───────────────────────────────────────────────────────────
  #
  # O Last Minute vende lavagem: TODAS as lavagens do estabelecimento, de
  # qualquer duração, pro cliente escolher o tipo que quer. Não existe teto de
  # tempo — se um serviço cabe antes do fechamento é decidido slot a slot
  # (closing_at na listagem, within_operating_hours no model), não por um
  # limite fixo que escondia a "Lavagem Completa" de todo mundo.
  #
  # Esta é a definição única da regra. Ela estava escrita à mão na listagem, no
  # checkout web, no card da home e na validação do agendamento — e as quatro
  # divergiram, fazendo a lista oferecer o que o backend recusava.
  WASH_CATEGORY       = "Lavagem".freeze
  WASH_TITLE_FALLBACK = "%lavagem%".freeze

  # `category` entrou depois em services, então cadastro antigo ficou com NULL
  # ou "". Sem o fallback pelo título, lava-rápido que só vende lavagem sumiria
  # inteiro do Last Minute. Com a categoria preenchida, ela manda.
  scope :last_minute, -> {
    where(
      "services.category = :cat OR " \
      "(COALESCE(TRIM(services.category), '') = '' AND LOWER(services.title) LIKE :fallback)",
      cat: WASH_CATEGORY, fallback: WASH_TITLE_FALLBACK
    )
  }

  belongs_to :car_wash
  has_many :appointments, dependent: :destroy

  validates :title, :price, :duration, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :duration, numericality: { greater_than: 0 }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  # Ajuste do Last Minute em %, por serviço: livre pra cima e pra baixo. Os
  # limites só evitam preço zerado e erro de digitação absurdo (10000%).
  validates :last_minute_pct, numericality: { only_integer: true, greater_than: -100, less_than_or_equal_to: 1000 }

  # Preço fixo por serviço (versão anterior) — substituído pelo ajuste em %.
  self.ignored_columns += ["last_minute_price"]

  # Preço no Last Minute: o preço do agendamento com o ajuste em % deste
  # serviço. O dono pode subir uma lavagem (urgência, taxa da Loov), baixar
  # outra (encher horário vago) e manter uma que já tem boa margem. Livre — o
  # cliente compara as lojas lado a lado. Reais inteiros (R$ 75, não R$ 74,75).
  def preco_last_minute
    pct = last_minute_pct.to_i
    return price.to_f if pct.zero?

    [(price.to_f * (100 + pct) / 100.0).round, 1].max.to_f
  end

  def preco_last_minute_proprio?
    preco_last_minute != price.to_f
  end

  # Versão em Ruby do scope acima, pra validar um serviço já em memória sem ida
  # ao banco. As duas precisam concordar.
  def last_minute?
    cat = category.to_s.strip
    return cat == WASH_CATEGORY if cat.present?
    title.to_s.downcase.include?("lavagem")
  end
end
