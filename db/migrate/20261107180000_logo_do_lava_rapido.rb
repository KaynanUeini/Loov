# Logo que o dono sobe: a chave do arquivo no bucket público de logos do R2
# (LogoStorage). Sem ele, o site e o app desenham o logo gerado pelo nome.
class LogoDoLavaRapido < ActiveRecord::Migration[7.1]
  def change
    add_column :car_washes, :logo_key, :string
  end
end
