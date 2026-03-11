class ChangeDayOfWeekTypeInOperatingHours < ActiveRecord::Migration[7.1]
  def up
    # Primeiro, adicionar uma nova coluna temporária para armazenar os valores convertidos
    add_column :operating_hours, :day_of_week_temp, :integer

    # Converter os valores existentes de string para inteiro
    OperatingHour.find_each do |hour|
      hour.update(day_of_week_temp: hour.day_of_week.to_i)
    end

    # Remover a coluna antiga
    remove_column :operating_hours, :day_of_week

    # Renomear a coluna temporária para o nome original
    rename_column :operating_hours, :day_of_week_temp, :day_of_week
  end

  def down
    # Reverter a mudança, transformando de volta para string
    add_column :operating_hours, :day_of_week_temp, :string

    OperatingHour.find_each do |hour|
      hour.update(day_of_week_temp: hour.day_of_week.to_s)
    end

    remove_column :operating_hours, :day_of_week
    rename_column :operating_hours, :day_of_week_temp, :day_of_week
  end
end
