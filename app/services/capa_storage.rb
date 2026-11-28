# Foto de capa da página do lava-rápido, no mesmo bucket público dos logos
# (LogoStorage), numa pasta própria. O site e o app enquadram a foto em
# 1200×600 (2:1) e mandam um JPG direto pro R2 por URL assinada.
class CapaStorage < LogoStorage
  # Um JPG de 1200×600 fica bem abaixo disso.
  TAMANHO_MAXIMO = 1.5.megabytes

  def self.prefixo(car_wash)
    "capas/#{car_wash.id}/"
  end

  def self.nova_chave(car_wash)
    "#{prefixo(car_wash)}#{SecureRandom.hex(8)}.jpg"
  end

  def url_envio(chave)
    presigner.presigned_url(:put_object, bucket: bucket, key: chave,
                            content_type: "image/jpeg", expires_in: UPLOAD_EXPIRA.to_i)
  end
end
