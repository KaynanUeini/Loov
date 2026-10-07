module Owner
  # Relatório financeiro detalhado do período — o que a tela de Financeiro
  # mostra em totais, aberto por serviço, canal, linha de custo e atendimento.
  #   GET /owner/financial_report.json  → dados (o app monta o PDF)
  #   GET /owner/financial_report.xlsx  → planilha pronta
  # Aceita os mesmos params da tela (period, start_date, end_date), pra o
  # relatório recortar exatamente o que o dono estava vendo.
  class FinancialReportsController < ApplicationController
    include FinancialPeriod

    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    # Só o dono: o relatório abre faturamento e lucro, que o atendente não vê.
    before_action :ensure_owner

    def show
      car_wash = current_user.linked_car_wash
      return render json: { error: "Você não tem um lava-rápido associado." }, status: :not_found if car_wash.nil?

      resolve_financial_period!
      period = params[:period].presence || "month"
      report = FinancialReport.new(
        car_wash:     car_wash,
        start_date:   @start_date,
        end_date:     @end_date,
        period:       period,
        period_label: build_period_label(@start_date, @end_date, period)
      )

      respond_to do |format|
        format.json { render json: report.data }
        format.xlsx do
          xlsx = FinancialReportXlsx.new(report.data)
          send_data xlsx.to_stream.read,
                    filename:    xlsx.filename,
                    type:        Mime[:xlsx].to_s,
                    disposition: "attachment"
        end
      end
    rescue Date::Error
      render json: { error: "Data inválida." }, status: :unprocessable_entity
    end

    private

    def ensure_owner
      render json: { error: "Acesso negado." }, status: :forbidden unless current_user&.owner?
    end
  end
end
