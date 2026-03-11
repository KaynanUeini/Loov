// application.js
console.log("application.js loaded");

// Initialize Stimulus controllers
const application = Stimulus.Application.start();

// Example controller registration (adjust based on your actual code)
application.register("example", class extends Stimulus.Controller {
  static targets = ["output"];
  connect() {
    console.log("Example controller connected");
  }
});

// Initialize available times functionality
function initializeAvailableTimes() {
  const dateInput = document.getElementById('appointment_date');
  const timeSelect = document.getElementById('appointment_time');

  if (dateInput && timeSelect) {
    dateInput.addEventListener('change', async () => {
      const date = dateInput.value;
      const carWashId = dateInput.dataset.carWashId;

      try {
        const response = await fetch(`/car_washes/${carWashId}/available_times?date=${date}`);
        const times = await response.json();

        timeSelect.innerHTML = '<option value="">Selecione um horário</option>';
        times.forEach(time => {
          const option = document.createElement('option');
          option.value = time;
          option.text = time;
          timeSelect.appendChild(option);
        });
      } catch (error) {
        console.error('Error fetching available times:', error);
      }
    });
  }
}

document.addEventListener('DOMContentLoaded', initializeAvailableTimes);
