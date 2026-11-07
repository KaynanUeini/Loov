# Logos dos lava-rápidos no Cloudflare R2, num bucket PÚBLICO só deles. O logo
# aparece pra qualquer visitante em listas com dezenas de lojas, então link
# assinado que vence (o da ficha do carro, FichaStorage) não serve: cada lista
# pediria um link por loja. As fotos da ficha continuam no bucket privado.
#
# Mesmas credenciais da ficha; o que muda é o bucket e o endereço público dele
# (o domínio r2.dev ou um domínio próprio ligado ao bucket).
#
# O site e o app tratam a imagem (public/logo/processa.js: tira fundo liso,
# corta margens, PNG 512×512 transparente) e enviam direto pro R2 por uma URL
# assinada (PUT), sem passar pelo nosso servidor.
class LogoStorage < FichaStorage
  # Um PNG de 512×512 fica bem abaixo disso; acima é arquivo que não passou
  # pela redução do site/app.
  TAMANHO_MAXIMO = 2.megabytes

  def self.configurado?
    %w[R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_LOGOS_BUCKET R2_LOGOS_URL].all? { |k| ENV[k].present? }
  end

  # Só aceita chaves que nós geramos pra este lava-rápido.
  def self.prefixo(car_wash)
    "logos/#{car_wash.id}/"
  end

  # Nome novo a cada troca: o endereço muda junto com a imagem, então nenhum
  # cache (navegador, app, CDN) segura o logo antigo.
  def self.nova_chave(car_wash)
    "#{prefixo(car_wash)}#{SecureRandom.hex(8)}.png"
  end

  # PNG: o logo guarda a transparência e fica com a forma dele (redondo,
  # escudo), sem fundo branco que viraria rebarba no card escuro.
  def url_envio(chave)
    presigner.presigned_url(:put_object, bucket: bucket, key: chave,
                            content_type: "image/png", expires_in: UPLOAD_EXPIRA.to_i)
  end

  def self.url_publica(chave)
    "#{ENV.fetch('R2_LOGOS_URL').chomp('/')}/#{chave}"
  end

  # Tamanho do arquivo enviado, ou nil se ele não existe.
  def tamanho(chave)
    client.head_object(bucket: bucket, key: chave).content_length
  rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
    nil
  end

  def apagar(chave)
    client.delete_object(bucket: bucket, key: chave)
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.warn("[LogoStorage] não apagou #{chave}: #{e.message}")
  end

  private

  def bucket = ENV.fetch("R2_LOGOS_BUCKET")
end
