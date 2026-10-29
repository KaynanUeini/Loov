require "aws-sdk-s3"

# Fotos da ficha do carro no Cloudflare R2 (compatível com S3), num bucket
# privado. O disco do Render é apagado a cada deploy, então foto não pode
# ficar no servidor.
#
# O app envia cada foto direto pro R2 por uma URL assinada (PUT), sem passar
# pelo nosso servidor — que no plano gratuito tem pouca memória e timeout
# curto. Pra ver, o servidor devolve URLs assinadas de leitura que vencem.
#
# Sem as variáveis R2_* configuradas, configurado? é falso e o app oferece só
# o modo desenho.
class FichaStorage
  UPLOAD_EXPIRA  = 10.minutes
  LEITURA_EXPIRA = 1.hour

  def self.configurado?
    %w[R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET].all? { |k| ENV[k].present? }
  end

  # Prefixo de todas as fotos de um atendimento: na hora de salvar a ficha,
  # só aceita chaves que nós geramos pra este atendimento.
  def self.prefixo(appointment)
    "fichas/#{appointment.car_wash_id}/#{appointment.id}/"
  end

  def self.nova_chave(appointment, label)
    "#{prefixo(appointment)}#{SecureRandom.hex(8)}-#{label}.jpg"
  end

  def url_envio(chave)
    presigner.presigned_url(:put_object, bucket: bucket, key: chave,
                            content_type: "image/jpeg", expires_in: UPLOAD_EXPIRA.to_i)
  end

  def url_leitura(chave)
    presigner.presigned_url(:get_object, bucket: bucket, key: chave,
                            expires_in: LEITURA_EXPIRA.to_i)
  end

  def existe?(chave)
    client.head_object(bucket: bucket, key: chave)
    true
  rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
    false
  end

  private

  def bucket = ENV.fetch("R2_BUCKET")

  def client
    @client ||= Aws::S3::Client.new(
      region:            "auto",
      endpoint:          "https://#{ENV.fetch('R2_ACCOUNT_ID')}.r2.cloudflarestorage.com",
      access_key_id:     ENV.fetch("R2_ACCESS_KEY_ID"),
      secret_access_key: ENV.fetch("R2_SECRET_ACCESS_KEY"),
      force_path_style:  true
    )
  end

  def presigner
    @presigner ||= Aws::S3::Presigner.new(client: client)
  end
end
