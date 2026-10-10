require "caxlsx"

# Planilha .xlsx do relatório financeiro. Recebe o hash de FinancialReport.
#
# Mesma família visual do PDF e da tela, traduzida pra planilha:
# - faixa escura no topo de cada aba (obsidian + título creme + eyebrow
#   coral): quem abre o arquivo sabe na hora de onde ele veio;
# - Resumo em cards lado a lado, como os KPIs do app, em vez de uma lista;
# - barras de dados nativas do Excel (coral = entrada, grafite = saída), as
#   mesmas barras do PDF;
# - respiro: margem lateral, linhas altas, fio fino em vez de grade.
# Totais saem como FÓRMULA, não número fixo: se o dono apagar uma linha pra
# simular cenário, a soma acompanha — é planilha, não PDF.
class FinancialReportXlsx
  OBSIDIAN = "1A1612".freeze
  INK      = "28231C".freeze
  GRAPHITE = "575148".freeze
  ASH      = "ADA699".freeze
  STONE    = "E0DBD0".freeze
  SAND     = "F1EEE6".freeze
  CREAM    = "FAFAF6".freeze
  CORAL    = "DD7852".freeze
  ROSE     = "C85050".freeze
  WHITE    = "FFFFFF".freeze
  FONT     = "Arial".freeze

  # Formato de moeda nativo pt-BR (o que o próprio Excel grava). Sem aspas
  # de propósito: o caxlsx não escapa aspas no styles.xml e o arquivo inteiro
  # de estilos sai corrompido. Sem [Red] também: o vermelho do Excel é fora
  # da paleta — o negativo ganha o rose da Loov pelo estilo da célula.
  FORMATS = {
    money: "[$R$-416] #,##0.00;-[$R$-416] #,##0.00",
    pct:   "0.0%;-0.0%",
    date:  "dd/mm/yyyy",
    rank:  "00"
  }.freeze

  SPACER = 2.5 # largura da coluna de margem lateral

  def initialize(report)
    @r = report
  end

  def to_stream
    package = Axlsx::Package.new
    package.use_shared_strings = true
    wb = package.workbook
    @styles = wb.styles
    @cache  = {}

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

  # ── Estilos ────────────────────────────────────────────────────────────────
  # Um estilo por combinação, criado sob demanda e reaproveitado. Evita a
  # tabela de 40 estilos nomeados e mantém cada célula declarando só o que
  # muda (cor, fundo, formato).
  #   sz, b, i, color, bg, fmt (:money/:pct/:int/:date), border
  #   (:hair/:strong/:none), h (:left/:right/:center), v, indent, wrap
  def sty(**o)
    @cache[o] ||= begin
      opts = {
        font_name: FONT, sz: o[:sz] || 10, b: o[:b] || false, i: o[:i] || false,
        fg_color: o[:color] || INK,
        alignment: {
          horizontal: o[:h] || :left, vertical: o[:v] || :center,
          indent: o[:indent] || 0, wrap_text: o[:wrap] || false
        }
      }
      opts[:bg_color] = o[:bg] if o[:bg]
      case o[:fmt]
      when :int then opts[:num_fmt] = 3
      when nil  then nil
      else opts[:format_code] = FORMATS.fetch(o[:fmt])
      end
      case o[:border]
      when :hair   then opts[:border] = { style: :thin, color: STONE, edges: [:bottom] }
      when :strong then opts[:border] = { style: :thin, color: INK,   edges: [:bottom] }
      when :top    then opts[:border] = { style: :thin, color: INK,   edges: [:top] }
      end
      @styles.add_style(opts)
    end
  end

  # Adiciona uma linha a partir de [valor, estilo] por célula (nil = vazia).
  # `formulas: true` só nas linhas de total montadas aqui: o caxlsx escapa
  # fórmulas por padrão (proteção contra injeção — um cliente cadastrado como
  # "=HYPERLINK(...)" não pode virar fórmula).
  def row(sheet, cells, height: 20, formulas: false, types: nil)
    values = cells.map { |c| c&.first }
    styles = cells.map { |c| c ? c[1] : sty }
    opts   = { style: styles, height: height }
    opts[:escape_formulas] = false if formulas
    opts[:types] = types if types
    sheet.add_row values, **opts
    sheet.rows.size
  end

  def blank(sheet, ncols, height: 12, bg: nil)
    row(sheet, Array.new(ncols) { [nil, bg ? sty(bg: bg) : sty] }, height: height)
  end

  def col(index)
    Axlsx.col_ref(index)
  end

  def pct(v)
    v.nil? ? nil : v.to_f / 100
  end

  def setup(sheet, landscape: false, tab: INK)
    sheet.sheet_view.show_grid_lines = false
    sheet.sheet_view.zoom_scale = 110
    sheet.sheet_pr.tab_color = "FF#{tab}"
    sheet.page_setup.set(orientation: landscape ? :landscape : :portrait, fit_to_width: 1, fit_to_height: 0)
    sheet.page_margins.set(left: 0.4, right: 0.4, top: 0.4, bottom: 0.5)
    sheet.print_options.horizontal_centered = true
  end

  # Faixa escura no topo — a "capa" de cada aba. Ela é o que diz de onde e de
  # quando o arquivo é quando uma aba é impressa ou repassada sozinha.
  def band(sheet, ncols, title)
    fill = ->(first, style) { [[nil, sty(bg: OBSIDIAN)], [first, style]] + Array.new(ncols - 2) { [nil, sty(bg: OBSIDIAN)] } }
    blank(sheet, ncols, height: 14, bg: OBSIDIAN)
    row(sheet, fill.("LOOV  ·  RELATÓRIO FINANCEIRO", sty(bg: OBSIDIAN, color: CORAL, sz: 8, b: true, v: :bottom)), height: 18)
    row(sheet, fill.(title, sty(bg: OBSIDIAN, color: CREAM, sz: 22, b: true)), height: 36)
    row(sheet, fill.("#{@r[:car_wash][:name]}  ·  #{@r[:period_label]}", sty(bg: OBSIDIAN, color: ASH, sz: 10, v: :top)), height: 20)
    blank(sheet, ncols, height: 12, bg: OBSIDIAN)
    blank(sheet, ncols, height: 22)
  end

  # Barra proporcional desenhada com REPT("█"), não com a barra de dados do
  # Excel: a do caxlsx sai com o degradê do Office 2007, que desmancha na
  # ponta. Bloco de texto colorido é sólido em Excel, Numbers e Google
  # Sheets, e segue sendo fórmula — muda o valor, a barra acompanha.
  # Escala pelo maior item (comparação de comprimento é o que o olho faz
  # melhor) e nunca negativa.
  BAR_STEPS = 20

  def bar(cell, range, color)
    ["=REPT(\"█\",MAX(0,ROUND(#{cell}/MAX(#{range})*#{BAR_STEPS},0)))",
     sty(sz: 7, color: color, border: :hair, indent: 1)]
  end

  def money_style(v, **extra)
    sty(fmt: :money, h: :right, color: v.to_f.negative? ? ROSE : (extra.delete(:color) || INK), **extra)
  end

  # Valor que sai do bolso (comissão): rose quando existe, cinza quando é
  # zero — R$ 0,00 em vermelho é alarme falso.
  def deduction_style(v, **extra)
    sty(fmt: :money, h: :right, color: v.to_f.zero? ? ASH : ROSE, **extra)
  end

  def head(label, right: false)
    [label, sty(sz: 8, b: true, color: GRAPHITE, border: :strong, v: :bottom, h: right ? :right : :left)]
  end

  # ── Resumo ─────────────────────────────────────────────────────────────────
  # Colunas: margem | card | vão | card | vão | card | vão | card | margem

  def resumo(wb)
    s = @r[:summary]
    loss = s[:profit].to_f.negative?
    wb.add_worksheet(name: "Resumo") do |sh|
      setup(sh, tab: CORAL)
      band(sh, 9, "Resumo")

      card_row(sh, [
        ["LUCRO LÍQUIDO", s[:profit], :money, "Faturamento menos custos", loss ? ROSE : CORAL],
        ["FATURAMENTO",   s[:revenue], :money, "Líquido de comissão"],
        ["CUSTOS",        s[:costs_total], :money, "Fixos + variáveis"],
        ["MARGEM",        pct(s[:margin]), :pct, "Lucro ÷ faturamento", loss ? ROSE : INK]
      ])
      blank(sh, 9, height: 10)
      card_row(sh, [
        ["ATENDIMENTOS",  s[:attended_count], :int, "Concluídos no período"],
        ["TICKET MÉDIO",  s[:avg_ticket], :money, "Por atendimento"],
        ["COMISSÃO LOOV", s[:commission], :money, "Só vagas Last Minute"],
        ["EM ABERTO",     s[:open_revenue], :money, "Agendado, a receber"]
      ])
      blank(sh, 9, height: 28)

      # Dois painéis lado a lado: de onde veio e pra onde foi.
      panel_title = ->(t) { [t, sty(sz: 13, b: true, border: :strong, v: :bottom)] }
      line_blank  = [nil, sty(border: :strong)]
      row(sh, [nil, panel_title.("Faturamento"), line_blank, line_blank, nil,
               panel_title.("Custos"), line_blank, line_blank, nil], height: 26)

      left = [
        ["Faturamento bruto", s[:gross_revenue], money_style(s[:gross_revenue], border: :hair)],
        ["Comissão Loov",     -s[:commission].to_f, deduction_style(s[:commission], border: :hair)],
        ["Faturamento líquido", s[:revenue], money_style(s[:revenue], b: true, border: :hair)]
      ]
      right = [
        ["Custos fixos",     s[:fixed_cost], money_style(s[:fixed_cost], border: :hair)],
        ["Custos variáveis", s[:variable_cost], money_style(s[:variable_cost], border: :hair)],
        ["Custos totais",    s[:costs_total], money_style(s[:costs_total], b: true, border: :hair)]
      ]
      left.zip(right).each_with_index do |(l, r), i|
        last = i == left.size - 1
        lab  = sty(border: :hair, b: last, color: last ? INK : GRAPHITE)
        row(sh, [nil, [l[0], lab], [nil, sty(border: :hair)], [l[1], l[2]], nil,
                 [r[0], lab], [nil, sty(border: :hair)], [r[1], r[2]], nil], height: 24)
      end

      notes.each do |n|
        blank(sh, 9, height: 10)
        r = row(sh, [nil, [n, sty(sz: 9, i: true, color: GRAPHITE, wrap: true, v: :top)]] + Array.new(7), height: 30)
        sh.merge_cells("B#{r}:H#{r}")
      end

      sh.column_widths SPACER, 24, SPACER, 24, SPACER, 24, SPACER, 24, SPACER
    end
  end

  # Fileira de 4 cards: rótulo / número grande / legenda, com fundo areia.
  def card_row(sheet, cards)
    gap = [nil, sty]
    build = lambda do |&cell|
      [gap] + cards.flat_map.with_index { |c, i| i < cards.size - 1 ? [cell.(c), gap] : [cell.(c)] } + [gap]
    end
    row(sheet, build.call { |c| [c[0], sty(bg: SAND, sz: 8, b: true, color: GRAPHITE, indent: 1, v: :bottom)] }, height: 24)
    row(sheet, build.call { |c| [c[1], sty(bg: SAND, sz: 18, b: true, fmt: c[2], color: c[4] || INK, indent: 1, h: :left)] }, height: 34)
    row(sheet, build.call { |c| [c[3], sty(bg: SAND, sz: 9, color: GRAPHITE, indent: 1, v: :top)] }, height: 22)
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
  # margem | # | Serviço | Categoria | Qtd | Ticket | Bruto | Comissão | Líquido | % | barra | margem

  def faturamento(wb)
    services = @r[:revenue_by_service]
    wb.add_worksheet(name: "Faturamento") do |sh|
      setup(sh, landscape: true)
      band(sh, 12, "Faturamento por serviço")

      row(sh, [nil, head("#"), head("SERVIÇO"), head("CATEGORIA"), head("QTD.", right: true),
               head("TICKET MÉDIO", right: true), head("BRUTO", right: true), head("COMISSÃO", right: true),
               head("LÍQUIDO", right: true), head("%", right: true), head(""), nil], height: 26)

      if services.empty?
        row(sh, [nil, nil, ["Nenhum atendimento concluído no período.", sty(i: true, color: GRAPHITE)]], height: 28)
      else
        first = sh.rows.size + 1
        services.each_with_index do |r, i|
          n = sh.rows.size + 1
          row(sh, [
            nil,
            [i + 1, sty(color: ASH, border: :hair, fmt: :rank, h: :left)],
            [r[:service], sty(b: true, border: :hair)],
            [r[:category].presence || "—", sty(color: GRAPHITE, border: :hair)],
            [r[:count], sty(fmt: :int, h: :right, border: :hair)],
            [r[:avg_ticket], money_style(r[:avg_ticket], border: :hair)],
            [r[:gross], money_style(r[:gross], border: :hair)],
            [-r[:commission].to_f, deduction_style(r[:commission], border: :hair)],
            [r[:net], money_style(r[:net], b: true, border: :hair)],
            [pct(r[:share]), sty(fmt: :pct, h: :right, color: GRAPHITE, border: :hair)],
            bar("I#{n}", "I$#{first}:I$#{first + services.size - 1}", CORAL),
            nil
          ], height: 24, formulas: true)
        end
        last = sh.rows.size

        t = last + 1
        tot = { bg: SAND, b: true, border: :top }
        row(sh, [
          nil, [nil, sty(**tot)], ["Total", sty(**tot)], [nil, sty(**tot)],
          ["=SUM(E#{first}:E#{last})", sty(**tot, fmt: :int, h: :right)],
          ["=IF(E#{t}=0,0,I#{t}/E#{t})", sty(**tot, fmt: :money, h: :right)],
          ["=SUM(G#{first}:G#{last})", sty(**tot, fmt: :money, h: :right)],
          ["=SUM(H#{first}:H#{last})", sty(**tot, fmt: :money, h: :right, color: @r[:summary][:commission].to_f.zero? ? ASH : ROSE)],
          ["=SUM(I#{first}:I#{last})", sty(**tot, fmt: :money, h: :right)],
          [1, sty(**tot, fmt: :pct, h: :right)],
          [nil, sty(**tot)], nil
        ], height: 26, formulas: true)
      end

      channels = @r[:revenue_by_channel]
      if channels.any?
        blank(sh, 12, height: 30)
        row(sh, [nil, nil, ["Por canal", sty(sz: 13, b: true, v: :bottom)]], height: 24)
        row(sh, [nil, head(""), head("CANAL"), head(""), head("QTD.", right: true), head(""), head(""),
                 head("COMISSÃO", right: true), head("LÍQUIDO", right: true), head("%", right: true), head(""), nil], height: 24)
        first = sh.rows.size + 1
        channels.each do |c|
          n = sh.rows.size + 1
          row(sh, [
            nil, [nil, sty(border: :hair)], [c[:label], sty(b: true, border: :hair)], [nil, sty(border: :hair)],
            [c[:count], sty(fmt: :int, h: :right, border: :hair)], [nil, sty(border: :hair)], [nil, sty(border: :hair)],
            [-c[:commission].to_f, deduction_style(c[:commission], border: :hair)],
            [c[:net], money_style(c[:net], b: true, border: :hair)],
            [pct(c[:share]), sty(fmt: :pct, h: :right, color: GRAPHITE, border: :hair)],
            bar("I#{n}", "I$#{first}:I$#{first + channels.size - 1}", CORAL), nil
          ], height: 24, formulas: true)
        end
      end

      sh.column_widths SPACER, 5, 32, 16, 8, 15, 15, 14, 16, 9, 22, SPACER
    end
  end

  # ── Custos ─────────────────────────────────────────────────────────────────
  # margem | Linha | Valor | % | barra | margem

  def custos(wb)
    c = @r[:costs]
    wb.add_worksheet(name: "Custos") do |sh|
      setup(sh)
      band(sh, 6, "Custos discriminados")

      if c[:lines].empty?
        row(sh, [nil, ["Nenhum custo lançado para este período.", sty(i: true, color: GRAPHITE)]], height: 28)
      else
        subtotals = []
        [["fixed", "Custos fixos"], ["variable", "Custos variáveis"]].each do |type, title|
          lines = c[:lines].select { |l| l[:type] == type }
          next if lines.empty?

          row(sh, [nil, [title, sty(sz: 13, b: true, v: :bottom)]], height: 26)
          row(sh, [nil, head("LINHA"), head("VALOR", right: true), head("%", right: true), head(""), nil], height: 22)
          first = sh.rows.size + 1
          lines.each do |l|
            n = sh.rows.size + 1
            row(sh, [
              nil, [l[:label], sty(border: :hair)],
              [l[:amount], money_style(l[:amount], border: :hair)],
              [pct(l[:share]), sty(fmt: :pct, h: :right, color: GRAPHITE, border: :hair)],
              bar("C#{n}", "C$#{first}:C$#{first + lines.size - 1}", GRAPHITE), nil
            ], height: 24, formulas: true)
          end
          last = sh.rows.size
          tot = { bg: SAND, b: true, border: :top }
          subtotals << row(sh, [
            nil, ["Subtotal", sty(**tot)],
            ["=SUM(C#{first}:C#{last})", sty(**tot, fmt: :money, h: :right)],
            ["=SUM(D#{first}:D#{last})", sty(**tot, fmt: :pct, h: :right)],
            [nil, sty(**tot)], nil
          ], height: 26, formulas: true)
          blank(sh, 6, height: 22)
        end

        # Total em faixa escura: fecha a aba com o mesmo tom da capa.
        dark = { bg: OBSIDIAN, color: CREAM, b: true }
        row(sh, [
          nil, ["Custos totais", sty(**dark, sz: 12, indent: 1)],
          ["=#{subtotals.map { |r| "C#{r}" }.join('+')}", sty(**dark, sz: 12, fmt: :money, h: :right)],
          [1, sty(**dark, fmt: :pct, h: :right)], [nil, sty(**dark)], nil
        ], height: 32, formulas: true)
      end

      sh.column_widths SPACER, 36, 18, 10, 30, SPACER
    end
  end

  # ── Mês a mês ──────────────────────────────────────────────────────────────
  # margem | Mês | Atend. | Faturamento | Custos | Lucro | Margem | barra | margem

  def mes_a_mes(wb)
    wb.add_worksheet(name: "Mês a mês") do |sh|
      setup(sh, landscape: true)
      band(sh, 9, "Mês a mês")

      row(sh, [nil, head("MÊS"), head("ATEND.", right: true), head("FATURAMENTO", right: true),
               head("CUSTOS", right: true), head("LUCRO", right: true), head("MARGEM", right: true),
               [" FATURAMENTO NO MÊS", sty(sz: 8, b: true, color: ASH, border: :strong, v: :bottom, indent: 1)], nil], height: 26)
      first = sh.rows.size + 1
      @r[:monthly].each do |m|
        n = sh.rows.size + 1
        row(sh, [
          nil, [m[:label], sty(b: true, border: :hair)],
          [m[:count], sty(fmt: :int, h: :right, border: :hair)],
          [m[:revenue], money_style(m[:revenue], border: :hair)],
          [m[:costs], money_style(m[:costs], border: :hair, color: GRAPHITE)],
          [m[:profit], money_style(m[:profit], b: true, border: :hair)],
          [pct(m[:margin]), sty(fmt: :pct, h: :right, color: m[:margin].to_f.negative? ? ROSE : GRAPHITE, border: :hair)],
          bar("D#{n}", "D$#{first}:D$#{first + @r[:monthly].size - 1}", CORAL), nil
        ], height: 24, formulas: true)
      end
      last = sh.rows.size

      t = last + 1
      profit = @r[:monthly].sum { |m| m[:profit] }
      tot = { bg: SAND, b: true, border: :top }
      row(sh, [
        nil, ["Total", sty(**tot)],
        ["=SUM(C#{first}:C#{last})", sty(**tot, fmt: :int, h: :right)],
        ["=SUM(D#{first}:D#{last})", sty(**tot, fmt: :money, h: :right)],
        ["=SUM(E#{first}:E#{last})", sty(**tot, fmt: :money, h: :right)],
        ["=SUM(F#{first}:F#{last})", sty(**tot, fmt: :money, h: :right, color: profit.negative? ? ROSE : INK)],
        ["=IF(D#{t}=0,\"\",F#{t}/D#{t})", sty(**tot, fmt: :pct, h: :right)],
        [nil, sty(**tot)], nil
      ], height: 26, formulas: true)

      sh.column_widths SPACER, 20, 12, 17, 17, 17, 11, 24, SPACER
    end
  end

  # ── Atendimentos ───────────────────────────────────────────────────────────
  # margem | Data | Hora | Cliente | Serviço | Canal | Bruto | Comissão | Líquido | margem

  def atendimentos(wb)
    list = @r[:appointments]
    wb.add_worksheet(name: "Atendimentos") do |sh|
      setup(sh, landscape: true)
      band(sh, 10, "Atendimentos")

      if list.empty?
        row(sh, [nil, ["Nenhum atendimento concluído no período.", sty(i: true, color: GRAPHITE)]], height: 28)
        sh.column_widths SPACER, 40
        next
      end

      # Total ACIMA da tabela, preso junto com o cabeçalho: numa lista de
      # 600 linhas, total no rodapé ninguém vê. SUBTOTAL respeita o filtro —
      # filtrou "Lavagem", o total vira o da lavagem.
      total_row = sh.rows.size + 1
      head_row  = total_row + 1
      first     = head_row + 1
      last      = first + list.size - 1
      tot = { bg: SAND, b: true }
      row(sh, [
        nil, ["Total exibido", sty(**tot, indent: 1)], [nil, sty(**tot)],
        ["=SUBTOTAL(3,B#{first}:B#{last})", sty(**tot, fmt: :int, h: :left)],
        [nil, sty(**tot)], [nil, sty(**tot)],
        ["=SUBTOTAL(9,G#{first}:G#{last})", sty(**tot, fmt: :money, h: :right)],
        ["=SUBTOTAL(9,H#{first}:H#{last})", sty(**tot, fmt: :money, h: :right, color: @r[:summary][:commission].to_f.zero? ? ASH : ROSE)],
        ["=SUBTOTAL(9,I#{first}:I#{last})", sty(**tot, fmt: :money, h: :right)], nil
      ], height: 28, formulas: true)

      row(sh, [nil, head("DATA"), head("HORA"), head("CLIENTE"), head("SERVIÇO"), head("CANAL"),
               head("BRUTO", right: true), head("COMISSÃO", right: true), head("LÍQUIDO", right: true), nil], height: 26)

      list.each do |a|
        service = a[:price_adjusted] ? "#{a[:service]} (preço ajustado)" : a[:service]
        row(sh, [
          nil,
          [Date.parse(a[:date]), sty(fmt: :date, border: :hair)],
          [a[:time], sty(color: GRAPHITE, border: :hair)],
          [a[:client], sty(border: :hair)],
          [service, sty(border: :hair)],
          [FinancialReport::CHANNELS[a[:channel]], sty(color: GRAPHITE, border: :hair)],
          [a[:gross], money_style(a[:gross], border: :hair)],
          [-a[:commission].to_f, deduction_style(a[:commission], border: :hair)],
          [a[:net], money_style(a[:net], b: true, border: :hair)],
          nil
        ], height: 20, types: [nil, :date, :string, :string, :string, :string, :float, :float, :float, nil])
      end

      sh.auto_filter = "B#{head_row}:I#{last}"
      sh.sheet_view.pane do |pane|
        pane.top_left_cell = "A#{first}"
        pane.state         = :frozen
        pane.y_split       = head_row
      end

      sh.column_widths SPACER, 12, 8, 26, 34, 24, 14, 14, 14, SPACER
    end
  end
end
