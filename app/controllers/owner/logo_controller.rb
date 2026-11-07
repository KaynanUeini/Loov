module Owner
  # Logo do lava-rápido (LogoStorage). Site e app usam os mesmos três passos:
  # pedem uma URL de envio, mandam a imagem direto pro R2 e confirmam aqui. Só
  # o dono troca; vale na hora, sem passar pelo "Salvar alterações".
  class LogoController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner
    before_action :set_car_wash
    before_action :ensure_storage

    # POST /owner/logo/envio → { key, url }
    def envio
      chave = LogoStorage.nova_chave(@car_wash)
      render json: { key: chave, url: LogoStorage.new.url_envio(chave) }
    end

    # PATCH /owner/logo { key } → { logo_url }
    def update
      chave   = params[:key].to_s
      storage = LogoStorage.new
      return erro("Envio inválido. Tente de novo.") unless chave.start_with?(LogoStorage.prefixo(@car_wash)) && chave.end_with?(".jpg")

      tamanho = storage.tamanho(chave)
      return erro("A imagem não chegou. Tente de novo.") if tamanho.nil?
      if tamanho > LogoStorage::TAMANHO_MAXIMO
        storage.apagar(chave)
        return erro("Imagem grande demais. Tente outra.")
      end

      antiga = @car_wash.logo_key
      @car_wash.update_columns(logo_key: chave, updated_at: Time.current)
      storage.apagar(antiga) if antiga.present? && antiga != chave
      render json: { logo_url: @car_wash.logo_url }
    end

    # DELETE /owner/logo → volta pro logo gerado pelo nome.
    def destroy
      antiga = @car_wash.logo_key
      @car_wash.update_columns(logo_key: nil, updated_at: Time.current)
      LogoStorage.new.apagar(antiga) if antiga.present?
      render json: { logo_url: nil }
    end

    private

    def erro(mensagem)
      render json: { error: mensagem }, status: :unprocessable_entity
    end

    def set_car_wash
      @car_wash = current_car_wash
      render json: { error: "Lava-rápido não encontrado." }, status: :not_found unless @car_wash
    end

    def ensure_owner
      render json: { error: "Só o dono troca o logo." }, status: :forbidden unless current_user&.owner?
    end

    def ensure_storage
      return if LogoStorage.configurado?
      render json: { error: "Envio de logo indisponível no momento." }, status: :service_unavailable
    end
  end
end
