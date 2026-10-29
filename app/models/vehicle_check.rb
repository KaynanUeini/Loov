# Ficha do carro: o estado do veículo registrado na entrada, por fotos ou
# pontos marcados no desenho visto de cima. É a prova do lava-rápido contra o
# "vocês riscaram meu carro" (ver a migração CriarFichasDoCarro).
#
# Pra valer como prova, depois de salva ninguém altera nem apaga — nem o dono.
# readonly? cobre update e destroy; só o expurgo de fichas vencidas (5 anos)
# apaga, com delete_all, que não passa por aqui.
class VehicleCheck < ApplicationRecord
  MODES  = %w[photos sketch skipped].freeze
  KINDS  = %w[risco amassado trincado outro].freeze
  # As 4 fotos guiadas são obrigatórias no modo fotos; detalhes são extras.
  PHOTO_LABELS = %w[front rear left right].freeze
  NOMES_FOTOS  = { "front" => "frente", "rear" => "traseira", "left" => "lado esquerdo", "right" => "lado direito" }.freeze
  MAX_DETAILS  = 4
  MAX_MARKS    = 30
  RETENCAO     = 5.years
  PLATE_FORMAT = /\A[A-Z]{3}[0-9][A-Z0-9][0-9]{2}\z/

  belongs_to :car_wash
  belongs_to :appointment
  belongs_to :recorded_by, class_name: "User"

  before_validation :normalizar, on: :create

  validates :mode, inclusion: { in: MODES }
  validates :plate, format: { with: PLATE_FORMAT, message: "inválida (ex: ABC1D23 ou ABC1234)" },
                    unless: :skipped?
  validate  :conteudo_do_modo

  scope :registradas, -> { where.not(mode: "skipped") }
  scope :vencidas,    -> { where("vehicle_checks.expires_at <= ?", Time.current) }

  def readonly? = persisted?

  def skipped? = mode == "skipped"

  # Onde fica um ponto (x, y de 0 a 1) no desenho visto de cima, frente em
  # cima: o lado esquerdo do desenho é o lado do motorista. As faixas batem com
  # o desenho do app (VehicleCheckScreen) — mudar uma, mudar a outra.
  def self.area_para(x, y)
    porta = x < 0.5 ? "esquerda" : "direita"   # a porta
    lado  = x < 0.5 ? "esquerdo" : "direito"   # o para-lama
    borda = x < 0.27 || x > 0.73
    case y
    when 0...0.09    then "para-choque dianteiro"
    when 0.09...0.29 then borda ? "para-lama dianteiro #{lado}" : "capô"
    when 0.29...0.40 then borda ? "porta dianteira #{porta}" : "para-brisa"
    when 0.40...0.55 then borda ? "porta dianteira #{porta}" : "teto"
    when 0.55...0.69 then borda ? "porta traseira #{porta}" : "teto"
    when 0.69...0.79 then borda ? "para-lama traseiro #{lado}" : "vidro traseiro"
    when 0.79...0.91 then borda ? "para-lama traseiro #{lado}" : "porta-malas"
    else                  "para-choque traseiro"
    end
  end

  private

  def normalizar
    self.plate = plate.to_s.upcase.gsub(/[^A-Z0-9]/, "").presence
    self.recorded_at = Time.current
    self.expires_at  = recorded_at + RETENCAO
    self.photos = Array(photos).map { |p| p.to_h.stringify_keys.slice("label", "key", "kind") }
    self.marks  = Array(marks).each_with_index.map do |m, i|
      m = m.to_h.stringify_keys
      x = m["x"].to_f.clamp(0.0, 1.0).round(4)
      y = m["y"].to_f.clamp(0.0, 1.0).round(4)
      { "n" => i + 1, "x" => x, "y" => y, "kind" => m["kind"].to_s, "area" => self.class.area_para(x, y) }
    end
    self.notes = notes.to_s.strip.first(500).presence
  end

  def conteudo_do_modo
    case mode
    when "photos"
      labels = photos.map { |p| p["label"] }
      faltando = PHOTO_LABELS - labels
      errors.add(:photos, "faltando: #{faltando.map { |l| NOMES_FOTOS[l] }.join(', ')}") if faltando.any?
      detalhes = labels.count("detail")
      errors.add(:photos, "no máximo #{MAX_DETAILS} detalhes") if detalhes > MAX_DETAILS
      guiadas = labels - ["detail"]
      if (guiadas - PHOTO_LABELS).any? || guiadas.uniq.size != guiadas.size
        errors.add(:photos, "inválidas")
      end
      photos.each do |p|
        errors.add(:photos, "tipo de avaria inválido") if p["kind"].present? && !KINDS.include?(p["kind"])
      end
    when "sketch"
      errors.add(:marks, "no máximo #{MAX_MARKS} pontos") if marks.size > MAX_MARKS
      errors.add(:marks, "tipo de avaria inválido") if marks.any? { |m| !KINDS.include?(m["kind"]) }
      errors.add(:photos, "não vão no modo desenho") if photos.any?
    when "skipped"
      errors.add(:base, "ficha pulada não tem fotos nem pontos") if photos.any? || marks.any?
    end
  end
end
