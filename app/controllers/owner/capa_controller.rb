module Owner
  # Foto de capa da página do lava-rápido (CapaStorage). Mesmos três passos do
  # logo: URL de envio, a imagem vai direto pro R2, confirmação aqui. Só o
  # dono troca; vale na hora, sem passar pelo "Salvar alterações".
  class CapaController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner
    before_action :set_car_wash
    before_action :ensure_storage

    # POST /owner/capa/envio → { key, url }
    def envio
      chave = CapaStorage.nova_chave(@car_wash)
      render json: { key: chave, url: CapaStorage.new.url_envio(chave) }
    end

    # PATCH /owner/capa { key } → { capa_url }
    def update
      chave   = params[:key].to_s
      storage = CapaStorage.new
      return erro("Envio inválido. Tente de novo.") unless chave.start_with?(CapaStorage.prefixo(@car_wash)) && chave.end_with?(".jpg")

      tamanho = storage.tamanho(chave)
      return erro("A foto não chegou. Tente de novo.") if tamanho.nil?
      if tamanho > CapaStorage::TAMANHO_MAXIMO
        storage.apagar(chave)
        return erro("Foto grande demais. Tente outra.")
      end

      antiga = @car_wash.capa_key
      @car_wash.update_columns(capa_key: chave, updated_at: Time.current)
      storage.apagar(antiga) if antiga.present? && antiga != chave
      render json: { capa_url: @car_wash.capa_url }
    end

    # DELETE /owner/capa → a página volta sem foto de capa.
    def destroy
      antiga = @car_wash.capa_key
      @car_wash.update_columns(capa_key: nil, updated_at: Time.current)
      CapaStorage.new.apagar(antiga) if antiga.present?
      render json: { capa_url: nil }
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
      render json: { error: "Só o dono troca a foto de capa." }, status: :forbidden unless current_user&.owner?
    end

    def ensure_storage
      return if CapaStorage.configurado?
      render json: { error: "Envio de foto indisponível no momento." }, status: :service_unavailable
    end
  end
end
