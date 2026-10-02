namespace :car_washes do
  desc "Tenta geocodificar de novo todo lava-rápido sem coordenada válida"
  task regeocode_missing: :environment do
    broken = CarWash.where(latitude: nil).or(CarWash.where(longitude: nil))
                     .or(CarWash.where(latitude: 0.0)).or(CarWash.where(longitude: 0.0))

    puts "#{broken.count} lava-rápido(s) sem coordenada válida."

    broken.find_each do |cw|
      coords = cw.geocode
      if coords
        cw.save!(validate: false)
        puts "OK  ##{cw.id} #{cw.name.inspect} -> #{coords.inspect}"
      else
        puts "FALHOU ##{cw.id} #{cw.name.inspect} (endereço: #{cw.geocoding_address.inspect}) -- nenhum degrau da cascata encontrou nada"
      end
      # Nominatim pede no máximo 1 req/s.
      sleep 1
    end
  end
end
