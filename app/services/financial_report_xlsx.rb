require "caxlsx"

# Planilha .xlsx do relatório financeiro. Recebe o hash de FinancialReport.
#
# Visual Loov em planilha: tinta escura sobre branco, um único acento coral
# (só no título e na linha de lucro), divisórias finas em vez de grade
# pesada. Totais saem como FÓRMULA, não número fixo: se o dono apagar uma
# linha pra simular cenário, a soma acompanha — é planilha, não PDF.
class FinancialReportXlsx
  INK      = "28231C".freeze
  GRAPHITE = "575148".freeze
  ASH      = "ADA699".freeze
  STONE    = "E0DBD0".freeze
  SAND     = "F1EEE6".freeze
  CORAL    = "DD7852".freeze
  ROSE     = "C85050".freeze
  FONT     = "Arial".freeze

  # Formato de moeda nativo pt-BR (o que o próprio Excel grava). Sem aspas
  # de propósito: o caxlsx não escapa aspas no styles.xml e o arquivo inteiro
  # de estilos sai corrompido. Sem [Red] também: o vermelho do Excel é fora
  # da paleta — o negativo ganha o rose da Loov pelo estilo da célula.
  MONEY = "[$R$-416] #,##0.00;-[$R$-416] #,##0.00".freeze
  PCT   = "0.0%".freeze

  def initialize(report)
    @r = report
  end

  def to_stream
    package = Axlsx::Package.new
    package.use_shared_strings = true
    wb = package.workbook
    @s = build_styles(wb.styles)

    resumo(wb)
    faturamento(wb)
    custos(wb)
    mes_a_mes(wb) if @r[:monthly].any?
    atendimentos(wb)

    package.to_stream
  end

  def filename
    base = @r[:period_label].to_s.tr("/", "-").gsub(/[^\p{Alnum}\- ]/, "").squeeze(" ").strip.tr(" ", "-")
    "Loov-Financeiro-#{base.presence || Date.current.iso8601}.xlsx"
  end

  private

  def build_styles(st)
    base   = { font_name: FONT, sz: 10, fg_color: INK }
    hair   = { style: :thin, color: STONE, edges: [:bottom] }
    strong = { style: :thin, color: INK,   edges: [:top] }
    {
      title:     st.add_style(base.merge(sz: 20, b: true)),
      subtitle:  st.add_style(base.merge(sz: 11, fg_color: GRAPHITE)),
      eyebrow:   st.add_style(base.merge(sz: 8, b: true, fg_color: CORAL)),
      section:   st.add_style(base.merge(sz: 12, b: true)),
      note:      st.add_style(base.merge(sz: 9, i: true, fg_color: GRAPHITE, alignment: { wrap_text: true, vertical: :top })),
      head:      st.add_style(base.merge(sz: 9, b: true, fg_color: GRAPHITE, bg_color: SAND, border: hair)),
      head_r:    st.add_style(base.merge(sz: 9, b: true, fg_color: GRAPHITE, bg_color: SAND, border: hair, alignment: { horizontal: :right })),
      text:      st.add_style(base.merge(border: hair)),
      muted:     st.add_style(base.merge(fg_color: GRAPHITE, border: hair)),
      int:       st.add_style(base.merge(border: hair, num_fmt: 3)),
      money:     st.add_style(base.merge(border: hair, format_code: MONEY)),
      money_neg: st.add_style(base.merge(border: hair, format_code: MONEY, fg_color: ROSE)),
      money_mut: st.add_style(base.merge(border: hair, format_code: MONEY, fg_color: ASH)),
      tot_neg:   st.add_style(base.merge(b: true, border: strong, format_code: MONEY, fg_color: ROSE)),
      pct:       st.add_style(base.merge(border: hair, format_code: PCT, fg_color: GRAPHITE)),
      tot_text:  st.add_style(base.merge(b: true, border: strong)),
      tot_int:   st.add_style(base.merge(b: true, border: strong, num_fmt: 3)),
      tot_money: st.add_style(base.merge(b: true, border: strong, format_code: MONEY)),
      tot_pct:   st.add_style(base.merge(b: true, border: strong, format_code: PCT)),
      kpi_label: st.add_style(base.merge(fg_color: GRAPHITE, border: hair)),
      kpi_money: st.add_style(base.merge(sz: 12, b: true, border: hair, format_code: MONEY)),
      kpi_int:   st.add_style(base.merge(sz: 12, b: true, border: hair, num_fmt: 3)),
      kpi_pct:   st.add_style(base.merge(sz: 12, b: true, border: hair, format_code: PCT)),
      kpi_hero:  st.add_style(base.merge(sz: 16, b: true, fg_color: CORAL, border: hair, format_code: MONEY)),
      kpi_loss:  st.add_style(base.merge(sz: 16, b: true, fg_color: ROSE,  border: hair, format_code: MONEY)),
      blank:     st.add_style(base)
    }
  end

  # Cabeçalho comum a todas as abas: o arquivo circula (contador, sócio), e
  # cada aba impressa sozinha precisa dizer de onde e de quando é.
  def header(sheet, title, cols)
    sheet.add_row ["LOOV · RELATÓRIO FINANCEIRO"] + [nil] * (cols - 1), style: @s[:eyebrow]
    sheet.add_row [title] + [nil] * (cols - 1), style: @s[:title], height: 28
    sheet.add_row ["#{@r[:car_wash][:name]} · #{@r[:period_label]}"] + [nil] * (cols - 1), style: @s[:subtitle]
    sheet.add_row []
  end

  # Linha de total com fórmulas. O caxlsx escapa fórmulas por padrão (proteção
  # contra injeção: um cliente cadastrado como "=HYPERLINK(...)" não pode
  # virar fórmula). Só estas linhas, montadas aqui dentro, saem sem escape.
  def formula_row(sheet, values, style:)
    sheet.add_row values, style: style, escape_formulas: false
  end

  # Valor que sai do bolso (comissão, prejuízo): rose quando existe, cinza
  # quando é zero — R$ 0,00 em vermelho é alarme falso.
  def deduction(v)
    v.to_f.zero? ? @s[:money_mut] : @s[:money_neg]
  end

  def signed(v, pos = :money, neg = :money_neg)
    v.to_f.negative? ? @s[neg] : @s[pos]
  end

  def pct(v)
    v.nil? ? nil : v.to_f / 100
  end

  def setup(sheet)
    sheet.sheet_view.show_grid_lines = false
    sheet.page_setup.set(orientation: :landscape, fit_to_width: 1, fit_to_height: 0)
    sheet.print_options.horizontal_centered = true
  end

  # ── Resumo ─────────────────────────────────────────────────────────────────

  def resumo(wb)
    s = @r[:summary]
    wb.add_worksheet(name: "Resumo") do |sh|
      setup(sh)
      header(sh, "Resumo", 2)

      sh.add_row ["Lucro líquido", s[:profit]], style: [@s[:kpi_label], signed(s[:profit], :kpi_hero, :kpi_loss)], height: 24
      [
        ["Faturamento líquido",  s[:revenue],        :kpi_money],
        ["Custos totais",        s[:costs_total],    :kpi_money],
        ["Margem",               pct(s[:margin]),    :kpi_pct],
        ["Atendimentos",         s[:attended_count], :kpi_int],
        ["Ticket médio",         s[:avg_ticket],     :kpi_money]
      ].each { |label, v, st| sh.add_row [label, v], style: [@s[:kpi_label], @s[st]], height: 20 }

      sh.add_row []
      sh.add_row ["Como o faturamento se compõe"], style: @s[:section]
      sh.add_row ["Faturamento bruto",  s[:gross_revenue]], style: [@s[:text], @s[:money]]
      sh.add_row ["Comissão Loov",      -s[:commission]],   style: [@s[:text], deduction(s[:commission])]
      sh.add_row ["Faturamento líquido", s[:revenue]],      style: [@s[:tot_text], @s[:tot_money]]
      sh.add_row ["Em aberto (agendado, ainda não atendido)", s[:open_revenue]], style: [@s[:muted], @s[:money]]

      sh.add_row []
      sh.add_row ["Como os custos se compõem"], style: @s[:section]
      sh.add_row ["Custos fixos",     s[:fixed_cost]],    style: [@s[:text], @s[:money]]
      sh.add_row ["Custos variáveis", s[:variable_cost]], style: [@s[:text], @s[:money]]
      sh.add_row ["Custos totais",    s[:costs_total]],   style: [@s[:tot_text], @s[:tot_money]]

      notes.each do |n|
        sh.add_row []
        sh.add_row [n], style: @s[:note], height: 30
        sh.merge_cells("A#{sh.rows.size}:B#{sh.rows.size}")
      end

      sh.column_widths 42, 22
    end
  end

  def notes
    list = []
    c = @r[:costs]
    if c[:prorated]
      list << "Custos rateados por dia: o período não cobre o mês inteiro, então cada custo mensal entra proporcional aos dias do período — a mesma conta do gráfico do app."
    end
    if c[:months_without_costs].any?
      list << "Sem custos lançados em: #{c[:months_without_costs].join(', ')}. O lucro desses meses aparece maior do que é."
    end
    list << "Gerado em #{Time.zone.parse(@r[:generated_at]).strftime('%d/%m/%Y às %H:%M')} pelo app Loov."
    list
  end

  # ── Faturamento ────────────────────────────────────────────────────────────

  def faturamento(wb)
    wb.add_worksheet(name: "Faturamento") do |sh|
      setup(sh)
      header(sh, "Faturamento por serviço", 7)

      sh.add_row ["Serviço", "Categoria", "Qtd.", "Ticket médio", "Bruto", "Comissão Loov", "Líquido", "% do total"],
                 style: [@s[:head]] * 2 + [@s[:head_r]] * 6
      first = sh.rows.size + 1
      @r[:revenue_by_service].each do |r|
        sh.add_row [r[:service], r[:category].presence || "—", r[:count], r[:avg_ticket], r[:gross], -r[:commission], r[:net], pct(r[:share])],
                   style: [@s[:text], @s[:muted], @s[:int], @s[:money], @s[:money], deduction(r[:commission]), @s[:money], @s[:pct]]
      end
      last = sh.rows.size
      if last >= first
        formula_row sh, ["Total", nil, "=SUM(C#{first}:C#{last})", "=IF(C#{last + 1}=0,0,G#{last + 1}/C#{last + 1})",
                    "=SUM(E#{first}:E#{last})", "=SUM(F#{first}:F#{last})", "=SUM(G#{first}:G#{last})", 1],
                   style: [@s[:tot_text], @s[:tot_text], @s[:tot_int], @s[:tot_money], @s[:tot_money], @s[:tot_money], @s[:tot_money], @s[:tot_pct]]
      else
        sh.add_row ["Nenhum atendimento no período."], style: @s[:note]
      end

      if @r[:revenue_by_channel].any?
        sh.add_row []
        sh.add_row ["Por canal"], style: @s[:section]
        sh.add_row ["Canal", nil, "Qtd.", nil, nil, "Comissão Loov", "Líquido", "% do total"],
                   style: [@s[:head]] * 2 + [@s[:head_r]] * 6
        @r[:revenue_by_channel].each do |r|
          sh.add_row [r[:label], nil, r[:count], nil, nil, -r[:commission], r[:net], pct(r[:share])],
                     style: [@s[:text], @s[:text], @s[:int], @s[:text], @s[:text], deduction(r[:commission]), @s[:money], @s[:pct]]
        end
      end

      sh.column_widths 34, 18, 8, 15, 15, 16, 16, 12
    end
  end

  # ── Custos ─────────────────────────────────────────────────────────────────

  def custos(wb)
    c = @r[:costs]
    wb.add_worksheet(name: "Custos") do |sh|
      setup(sh)
      header(sh, "Custos discriminados", 4)

      if c[:lines].empty?
        sh.add_row ["Nenhum custo lançado para este período."], style: @s[:note]
      else
        subtotal_cells = []
        [["fixed", "Custos fixos"], ["variable", "Custos variáveis"]].each do |type, title|
          lines = c[:lines].select { |l| l[:type] == type }
          next if lines.empty?

          sh.add_row [title, nil, "Valor", "% dos custos"], style: [@s[:head], @s[:head], @s[:head_r], @s[:head_r]]
          first = sh.rows.size + 1
          lines.each do |l|
            sh.add_row [l[:label], nil, l[:amount], pct(l[:share])], style: [@s[:text], @s[:text], @s[:money], @s[:pct]]
          end
          last = sh.rows.size
          formula_row sh, ["Subtotal", nil, "=SUM(C#{first}:C#{last})", "=SUM(D#{first}:D#{last})"],
                     style: [@s[:tot_text], @s[:tot_text], @s[:tot_money], @s[:tot_pct]]
          subtotal_cells << sh.rows.size
          sh.add_row []
        end
        formula_row sh, ["Custos totais", nil, "=#{subtotal_cells.map { |r| "C#{r}" }.join('+')}", 1],
                   style: [@s[:tot_text], @s[:tot_text], @s[:tot_money], @s[:tot_pct]]
      end

      sh.column_widths 34, 4, 18, 14
    end
  end

  # ── Mês a mês ──────────────────────────────────────────────────────────────

  def mes_a_mes(wb)
    wb.add_worksheet(name: "Mês a mês") do |sh|
      setup(sh)
      header(sh, "Mês a mês", 6)

      sh.add_row ["Mês", "Atendimentos", "Faturamento", "Custos", "Lucro", "Margem"],
                 style: [@s[:head]] + [@s[:head_r]] * 5
      first = sh.rows.size + 1
      @r[:monthly].each do |m|
        sh.add_row [m[:label], m[:count], m[:revenue], m[:costs], m[:profit], pct(m[:margin])],
                   style: [@s[:text], @s[:int], @s[:money], @s[:money], signed(m[:profit]), @s[:pct]]
      end
      last = sh.rows.size
      t    = last + 1
      formula_row sh, ["Total", "=SUM(B#{first}:B#{last})", "=SUM(C#{first}:C#{last})", "=SUM(D#{first}:D#{last})",
                  "=SUM(E#{first}:E#{last})", "=IF(C#{t}=0,\"\",E#{t}/C#{t})"],
                 style: [@s[:tot_text], @s[:tot_int], @s[:tot_money], @s[:tot_money],
                         @s[@r[:monthly].sum { |m| m[:profit] }.negative? ? :tot_neg : :tot_money], @s[:tot_pct]]

      sh.column_widths 20, 14, 16, 16, 16, 10
    end
  end

  # ── Atendimentos ───────────────────────────────────────────────────────────

  def atendimentos(wb)
    wb.add_worksheet(name: "Atendimentos") do |sh|
      setup(sh)
      header(sh, "Atendimentos", 8)

      sh.add_row ["Data", "Hora", "Cliente", "Serviço", "Canal", "Bruto", "Comissão Loov", "Líquido"],
                 style: [@s[:head]] * 5 + [@s[:head_r]] * 3
      head_row = sh.rows.size
      date_style = wb.styles.add_style(font_name: FONT, sz: 10, fg_color: INK, format_code: "dd/mm/yyyy", alignment: { horizontal: :left },
                                       border: { style: :thin, color: STONE, edges: [:bottom] })
      @r[:appointments].each do |a|
        service = a[:price_adjusted] ? "#{a[:service]} (preço ajustado)" : a[:service]
        sh.add_row [Date.parse(a[:date]), a[:time], a[:client], service, FinancialReport::CHANNELS[a[:channel]],
                    a[:gross], -a[:commission], a[:net]],
                   style: [date_style, @s[:muted], @s[:text], @s[:text], @s[:muted], @s[:money], deduction(a[:commission]), @s[:money]],
                   types: [:date, :string, :string, :string, :string, :float, :float, :float]
      end
      last = sh.rows.size

      if last > head_row
        sh.auto_filter = "A#{head_row}:H#{last}"
        formula_row sh, ["Total", nil, nil, nil, nil, "=SUBTOTAL(9,F#{head_row + 1}:F#{last})",
                    "=SUBTOTAL(9,G#{head_row + 1}:G#{last})", "=SUBTOTAL(9,H#{head_row + 1}:H#{last})"],
                   style: [@s[:tot_text]] * 5 + [@s[:tot_money]] * 3
      else
        sh.add_row ["Nenhum atendimento no período."], style: @s[:note]
      end

      # Cabeçalho da tabela fica fixo ao rolar a lista.
      sh.sheet_view.pane do |pane|
        pane.top_left_cell = "A#{head_row + 1}"
        pane.state         = :frozen
        pane.y_split       = head_row
      end

      sh.column_widths 12, 8, 26, 34, 24, 14, 16, 14
    end
  end
end
