# Quando a pausa começou. Sem isso a barra de tempo restante não teria
# denominador — daria pra desenhar, mas seria uma barra que não mede nada.
class AddPausedAtToCarWashes < ActiveRecord::Migration[7.1]
  def change
    add_column :car_washes, :paused_at, :datetime unless column_exists?(:car_washes, :paused_at)
  end
end
