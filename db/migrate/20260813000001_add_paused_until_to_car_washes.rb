# Pausa do Last Minute. Nullable de propósito: NULL é "não pausado", e assim
# todo lava-rápido existente já nasce disponível sem backfill.
class AddPausedUntilToCarWashes < ActiveRecord::Migration[7.1]
  def change
    add_column :car_washes, :paused_until, :datetime unless column_exists?(:car_washes, :paused_until)
  end
end
