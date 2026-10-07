# Período financeiro (Hoje / Semana / Mês / Ano / Intervalo) lido dos params.
# Compartilhado entre a tela de Financeiro e o relatório exportado: os dois
# precisam recortar exatamente os mesmos dias, senão o PDF não bate com o
# gráfico que o dono acabou de ver.
module FinancialPeriod
  extend ActiveSupport::Concern

  private

  # Define @start_date, @end_date e @granularity a partir de params[:period]
  # (e start_date/end_date quando o período é "custom").
  def resolve_financial_period!
    @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : Date.current.beginning_of_month
    @end_date   = params[:end_date].present?   ? Date.parse(params[:end_date])   : Date.current.end_of_month

    unless params[:period].present?
      @granularity = "day"
      return
    end

    case params[:period]
    when "day"
      @start_date  = Date.current
      @end_date    = Date.current
      @granularity = "hour"
    when "week"
      @start_date  = Date.current.beginning_of_week(:monday)
      @end_date    = Date.current.end_of_week(:monday)
      @granularity = "day"
    when "month"
      @start_date  = Date.current.beginning_of_month
      @end_date    = Date.current.end_of_month
      @granularity = "day"
    when "year"
      @start_date  = Date.current.beginning_of_year
      @end_date    = Date.current.end_of_year
      @granularity = "month"
    when "all"
      @start_date  = Date.new(2025, 1, 1)
      @end_date    = Date.current.end_of_year
      @granularity = "year"
    when "custom"
      @start_date  = params[:start_date].present? ? Date.parse(params[:start_date]) : Date.current.beginning_of_month
      @end_date    = params[:end_date].present?   ? Date.parse(params[:end_date])   : Date.current.end_of_month
      @granularity = "month"
    else
      @start_date  = Date.current.beginning_of_month
      @end_date    = Date.current.end_of_month
      @granularity = "day"
    end
  end

  def build_period_label(start_date, end_date, period)
    case period
    when "day"    then start_date.strftime("%d/%m/%Y")
    when "week"   then "#{start_date.strftime('%d/%m')} – #{end_date.strftime('%d/%m')}"
    when "month"  then "#{MonthlyCost::MONTH_NAMES[start_date.month - 1]} #{start_date.year}"
    when "year"   then start_date.year.to_s
    when "custom" then "#{start_date.strftime('%d/%m/%y')} – #{end_date.strftime('%d/%m/%y')}"
    when "all"    then "Desde #{start_date.strftime('%d/%m/%Y')}"
    else "#{start_date.strftime('%d/%m')} – #{end_date.strftime('%d/%m')}"
    end
  end
end
