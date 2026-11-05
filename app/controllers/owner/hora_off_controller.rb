module Owner
  # Hora Off e Hora Pico do lava-rápido (ver PrecoDinamico): a grade de
  # horários fracos e fortes, os limites e as duas funções. Site e app usam os
  # mesmos dois endpoints. O atendente vê; só o dono muda, porque mexe no preço
  # do lava-rápido inteiro.
  class HoraOffController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner_or_attendant
    before_action :set_car_wash
    before_action :ensure_owner, only: [:update]

    LIMITES = {
      hora_off_desconto_max: 5..50,
      margem_minima:         0..80,
      hora_pico_pct:         0..30,
      taxas_venda_pct:       0..30
    }.freeze
    CUSTO_MAXIMO = 1000 # R$ por lavagem: acima disso é erro de digitação

    # GET /owner/hora_off
    def show
      render json: payload
    end

    # PATCH /owner/hora_off
    #   { hora_off_enabled, hora_pico_enabled, chuva_enabled,
    #     desconto_max, margem_minima, pico_pct, taxas_pct,
    #     custo_lavagem (R$; vazio ou null tira o piso),
    #     grade: [{ dia, faixa, nivel }], servicos: [{ id, incluido }] }
    # Tudo opcional: manda só o que mudou.
    def update
      attrs = {}
      { hora_off_enabled: :hora_off_enabled, hora_pico_enabled: :hora_pico_enabled,
        chuva_enabled: :hora_off_chuva_enabled }.each do |param, coluna|
        attrs[coluna] = bool(params[param]) if params.key?(param)
      end
      { desconto_max: :hora_off_desconto_max, margem_minima: :margem_minima,
        pico_pct: :hora_pico_pct, taxas_pct: :taxas_venda_pct }.each do |param, coluna|
        next unless params.key?(param)
        valor = Integer(params[param].to_s, exception: false)
        return erro("Valor inválido em #{param}.") unless valor && LIMITES[coluna].cover?(valor)
        attrs[coluna] = valor
      end
      if params.key?(:custo_lavagem)
        bruto = params[:custo_lavagem].to_s.strip.tr(",", ".")
        if bruto.empty?
          attrs[:custo_lavagem] = nil
        else
          custo = Float(bruto, exception: false)
          return erro("Custo por lavagem inválido.") unless custo && custo >= 0 && custo <= CUSTO_MAXIMO
          attrs[:custo_lavagem] = custo.zero? ? nil : custo.round(2)
        end
      end

      celulas  = Array(params[:grade]).map { |c| c.respond_to?(:permit) ? c.permit(:dia, :faixa, :nivel).to_h : c.to_h }
      servicos = Array(params[:servicos]).map { |s| s.respond_to?(:permit) ? s.permit(:id, :incluido).to_h : s.to_h }
      celulas.each do |c|
        dia = Integer(c["dia"].to_s, exception: false)
        unless dia&.between?(0, 6) && DemandCell::FAIXAS.include?(c["faixa"]) && DemandCell::NIVEIS.include?(c["nivel"])
          return erro("Horário inválido na grade.")
        end
      end

      ActiveRecord::Base.transaction do
        @car_wash.update!(attrs) if attrs.any?
        celulas.each { |c| gravar_celula(c["dia"].to_i, c["faixa"], c["nivel"]) }
        servicos.each do |s|
          servico = @car_wash.services.find_by(id: s["id"])
          next unless servico
          # Igual ao padrão da categoria, volta a seguir a categoria (nil).
          incluido = bool(s["incluido"])
          servico.update_columns(hora_off_incluido: incluido == servico.last_minute? ? nil : incluido, updated_at: Time.current)
        end
      end
      @car_wash.demand_cells.reset
      render json: payload
    end

    private

    def gravar_celula(dia, faixa, nivel)
      celula = @car_wash.demand_cells.find_by(dia: dia, faixa: faixa)
      # O que bate com o padrão não fica gravado: se o padrão melhorar, quem
      # não mexeu naquele horário acompanha.
      if nivel == DemandCell.nivel_padrao(dia, faixa)
        celula&.destroy!
      elsif celula
        celula.update!(nivel: nivel)
      else
        @car_wash.demand_cells.create!(dia: dia, faixa: faixa, nivel: nivel)
      end
    end

    def payload
      precos = PrecoDinamico.new(@car_wash)
      dias   = @car_wash.operating_hours.map(&:day_of_week).uniq.sort
      {
        hora_off_enabled:  @car_wash.hora_off_enabled,
        hora_pico_enabled: @car_wash.hora_pico_enabled,
        chuva_enabled:     @car_wash.hora_off_chuva_enabled,
        desconto_max:      @car_wash.hora_off_desconto_max,
        margem_minima:     @car_wash.margem_minima,
        pico_pct:          @car_wash.hora_pico_pct,
        taxas_pct:         @car_wash.taxas_venda_pct,
        custo_lavagem:     @car_wash.custo_lavagem&.to_f,
        taxa_loov_last_minute: PrecoDinamico::TAXA_LOOV_LAST_MINUTE,
        escada:            PrecoDinamico::ESCADA.map { |limite, pct| { minutos: (limite / 1.minute).to_i, pct: pct } },
        desconto_last_minute: PrecoDinamico::DESCONTO_LAST_MINUTE,
        extra_chuva:       PrecoDinamico::EXTRA_CHUVA,
        limites:           LIMITES.transform_values { |r| { min: r.min, max: r.max } },
        dias:              dias,
        faixas:            @car_wash.faixas_da_grade,
        grade:             dias.flat_map { |dia|
                             @car_wash.faixas_da_grade.map { |faixa|
                               nivel = @car_wash.nivel_demanda_em(dia, faixa)
                               { dia: dia, faixa: faixa, nivel: nivel, padrao: nivel == DemandCell.nivel_padrao(dia, faixa) }
                             }
                           },
        # Sem custo informado, o piso não existe e o painel pede o custo.
        piso:              precos.piso(false),
        piso_last_minute:  precos.piso(true),
        servicos:          @car_wash.services.order(:price).map { |s|
                             faixa = precos.faixa(s)
                             piso  = precos.piso(true)
                             { id: s.id, title: s.title, price: s.price.to_f,
                               incluido: precos.aplica?(s), incluido_padrao: s.last_minute?,
                               min: faixa[:min], max: faixa[:max],
                               # Piso a 10% da tabela ou menos: quase não sobra
                               # desconto, e o painel avisa.
                               piso_trava: !!(piso && piso >= s.price.to_f * 0.9) }
                           }
      }
    end

    def bool(valor)
      ActiveModel::Type::Boolean.new.cast(valor) || false
    end

    def erro(mensagem)
      render json: { error: mensagem }, status: :unprocessable_entity
    end

    def set_car_wash
      @car_wash = current_car_wash
      render json: { error: "Lava-rápido não encontrado." }, status: :not_found unless @car_wash
    end

    def ensure_owner_or_attendant
      return if current_user&.owner? || current_user&.attendant?
      render json: { error: "Acesso negado." }, status: :forbidden
    end

    def ensure_owner
      render json: { error: "Só o dono muda a Hora Off e a Hora Pico." }, status: :forbidden unless current_user&.owner?
    end
  end
end
