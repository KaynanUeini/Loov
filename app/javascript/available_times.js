// Definir a função updateAvailableTimes no escopo global
window.updateAvailableTimes = function(date, carWashId, serviceId, duration) {
  console.log('updateAvailableTimes called with:', { date, carWashId, serviceId, duration });

  if (!date) {
    console.log('No date provided, returning early');
    return;
  }

  const timeSelect = document.getElementById(`scheduled_at_time_${serviceId}`);
  if (!timeSelect) {
    console.log('Time select element not found for serviceId:', serviceId);
    return;
  }

  timeSelect.innerHTML = '<option value="">Carregando...</option>';
  console.log('Fetching available times for URL:', `/car_washes/${carWashId}/available_times?date=${date}&service_id=${serviceId}&duration=${duration}`);

  // Adicionar timeout de 10 segundos na requisição (para depuração)
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 10000);

  fetch(`/car_washes/${carWashId}/available_times?date=${date}&service_id=${serviceId}&duration=${duration}`, {
    headers: {
      'Accept': 'application/json'
    },
    signal: controller.signal
  })
  .then(response => {
    clearTimeout(timeoutId);
    console.log('Fetch response status:', response.status);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    return response.json();
  })
  .then(data => {
    console.log('Available times received:', data);
    timeSelect.innerHTML = '<option value="">Selecione o horário</option>';
    data.forEach(time => {
      const option = document.createElement('option');
      option.value = time;
      option.text = time;
      timeSelect.appendChild(option);
    });

    if (data.length === 0) {
      timeSelect.innerHTML = '<option value="">Nenhum horário disponível</option>';
    }
  })
  .catch(error => {
    clearTimeout(timeoutId);
    console.error('Erro ao carregar horários disponíveis:', error);
    timeSelect.innerHTML = '<option value="">Erro ao carregar horários</option>';
  });
};

// Função para inicializar os event listeners
function initializeAvailableTimes() {
  console.log("Initializing available times event listeners");

  const dateFields = document.querySelectorAll("input[name='appointment[scheduled_at_date]']");
  console.log("Date fields found:", dateFields.length);

  if (dateFields.length === 0) {
    console.warn("Nenhum campo de data encontrado. Verifique se os campos estão presentes na página.");
    return;
  }

  dateFields.forEach(dateField => {
    console.log("Adding change event listener to date field:", dateField);

    dateField.addEventListener("change", (event) => {
      console.log("Date field changed:", event.target.value);

      const date = event.target.value;
      const form = dateField.closest("form");
      if (!form) {
        console.error("Formulário não encontrado para o campo de data:", dateField);
        return;
      }

      const serviceIdField = form.querySelector("input[name='appointment[service_id]']");
      const carWashIdField = form.querySelector("input[name='appointment[car_wash_id]']");
      const durationField = form.querySelector("input[name='appointment[duration]']");

      if (!serviceIdField || !carWashIdField) {
        console.error("Campos service_id ou car_wash_id não encontrados no formulário:", form);
        return;
      }

      const serviceId = serviceIdField.value;
      const carWashId = carWashIdField.value;
      let duration = 30; // Duração padrão em minutos
      if (durationField) {
        duration = durationField.value;
      } else {
        console.warn("Campo duration não encontrado. Usando duração padrão:", duration);
      }

      window.updateAvailableTimes(date, carWashId, serviceId, duration);
    });
  });
}

// Inicializar os event listeners quando a página for carregada
document.addEventListener("turbo:load", () => {
  console.log("Turbo:load event fired (available_times.js)");
  initializeAvailableTimes();
});

document.addEventListener("DOMContentLoaded", () => {
  console.log("DOMContentLoaded event fired (available_times.js)");
  initializeAvailableTimes();
});

// Fallback: Tentar inicializar imediatamente após o script ser carregado
console.log("Attempting immediate initialization (fallback)");
initializeAvailableTimes();

// Log para confirmar que o script foi carregado
console.log("available_times.js loaded");
