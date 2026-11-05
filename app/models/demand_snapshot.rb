# Foto semanal da grade da Hora Off e da Hora Pico. A grade é o que a Loov
# previu; o que aconteceu já está nos agendamentos. Comparar os dois, semana a
# semana, é como o aprendizado vai ser medido antes de mexer no preço sozinho.
class DemandSnapshot < ApplicationRecord
  belongs_to :car_wash

  validates :semana, presence: true

  # Uma foto por semana, tirada na primeira passada dela (o gatilho é diário).
  # Só de quem tem a Hora Off ou a Hora Pico ligada: a grade dos outros não
  # decide preço nenhum.
  def self.registrar_semana!(hoje = Date.current)
    semana = hoje.beginning_of_week(:monday)
    criadas = 0
    CarWash.where(active: true)
           .where("hora_off_enabled OR hora_pico_enabled")
           .where.not(id: where(semana: semana).select(:car_wash_id))
           .includes(:demand_cells)
           .find_each do |cw|
      create!(car_wash: cw, semana: semana, grade: cw.grade_demanda)
      criadas += 1
    rescue ActiveRecord::RecordNotUnique
      next
    end
    criadas
  end
end
