// app/javascript/appointments.js
window.app = {
  window.app = {
    initAppointments: function() {
      {
        console.log("Script principal iniciado com sucesso");

      // Inicializar Flatpickr
        const fp = flatpickr("#appointment-date", {
          dateFormat: "Y-m-d",
          altInput: true,
          altFormat: "d/m/Y",
          minDate: new Date().setHours(0, 0, 0, 0),
          maxDate: new Date(new Date().setDate(new Date().getDate() + 14)),
          locale: {
            firstDayOfWeek: 0,
            weekdays: { shorthand: ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sab"], longhand: ["Domingo", "Segunda", "Terca", "Quarta", "Quinta", "Sexta", "Sabado"] },
            months: { shorthand: ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"], longhand: ["Janeiro", "Fevereiro", "Marco", "Abril", "Maio", "Junho", "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"] },
          },
          onChange: async function(selectedDates, dateStr, instance) {
            console.log("Flatpickr onChange disparado");
            if (selectedDates && selectedDates.length > 0) {
              const selectedDate = selectedDates[0];
              const formattedDate = selectedDate.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric' }).replace(/\//g, '/');
              document.getElementById('summary-date').textContent = formattedDate;
              document.getElementById('time-error').style.display = 'none';

              const result = await prepareTimePicker(dateStr, window.operatingHours, window.capacityPerSlot);
              if (result.error) {
                showErrorMessage(result.error, 5000);
                document.getElementById('time-slots').style.display = 'none';
                document.getElementById('appointment-time').value = '';
                document.getElementById('summary-time').textContent = 'Nao selecionado';
                return;
              }
              const { availableSlots } = result;
              if (availableSlots.length === 0) {
                showErrorMessage('Nao ha horarios disponiveis para o dia selecionado.', 5000);
                document.getElementById('time-slots').style.display = 'none';
                document.getElementById('appointment-time').value = '';
                document.getElementById('summary-time').textContent = 'Nao selecionado';
                return;
              }
              renderTimeSlots(availableSlots);
              document.getElementById('time-slots').style.display = 'flex';
              selectTimeSlot(availableSlots[0].start, `${availableSlots[0].start} (${availableSlots[0].capacity})`);
            } else {
              document.getElementById('summary-date').textContent = 'Nao selecionado';
              document.getElementById('time-slots').style.display = 'none';
              document.getElementById('appointment-time').value = '';
              document.getElementById('summary-time').textContent = 'Nao selecionado';
            }
          }
        });
        console.log("Flatpickr inicializado:", fp);

      // Função de debounce
        function debounce(func, wait) {
          let timeout;
          return function (...args) {
            clearTimeout(timeout);
            timeout = setTimeout(() => func.apply(this, args), wait);
          };
        }

      // Função para exibir mensagem de erro
        function showErrorMessage(message, duration = 3000) {
          const errorDiv = document.getElementById('time-error');
          errorDiv.querySelector('p').textContent = message;
          errorDiv.style.display = 'block';
          setTimeout(() => { errorDiv.style.display = 'none'; }, duration);
        }

      // Função para formatar data
        function formatDateToDDMMYYYY(date) {
          const day = date.getDate().toString().padStart(2, '0');
          const month = (date.getMonth() + 1).toString().padStart(2, '0');
          const year = date.getFullYear();
          return `${day}/${month}/${year}`;
        }

      // Função para converter HH:mm para minutos
        function timeToMinutes(timeStr) {
          if (!timeStr || typeof timeStr !== 'string') { console.warn('timeStr invalido:', timeStr); return 0; }
          const timeMatch = timeStr.match(/T(\d{2}:\d{2}:\d{2})/);
          if (!timeMatch) { console.warn('Formato de horario invalido em timeStr:', timeStr); return 0; }
          const [hours, minutes] = timeMatch[1].split(':').map(Number);
          return hours * 60 + minutes;
        }

      // Função para converter minutos para HH:mm
        function minutesToTime(minutes) {
          const hours = Math.floor(minutes / 60);
          const mins = minutes % 60;
          return `${hours.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}`;
        }

      // Função para comparar datas
        function isSameDay(date1, date2) {
          return date1.getUTCFullYear() === date2.getUTCFullYear() &&
          date1.getUTCMonth() === date2.getUTCMonth() &&
          date1.getUTCDate() === date2.getUTCDate();
        }

      // Função para ajustar fuso horário
        function getDateInSaoPauloTimezone(dateStr) {
          const [year, month, day] = dateStr.split('-').map(Number);
          return new Date(year, month - 1, day, 0, 0, 0);
        }

      // Função para buscar agendamentos
        async function fetchAppointments(date) {
          try {
            const response = await fetch(`/appointments.json?car_wash_id=${window.carWashId}&date=${date}`, {
              method: 'GET',
              headers: { 'Accept': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content }
            });
            if (!response.ok) throw new Error(await response.text());
            const data = await response.json();
            return data.appointments || [];
          } catch (e) {
            console.error('Erro ao buscar agendamentos:', e.message);
            return [];
          }
        }

      // Função para preparar time picker
        async function prepareTimePicker(selectedDate, operatingHours, capacityPerSlot) {
          const date = getDateInSaoPauloTimezone(selectedDate);
          const dayOfWeek = date.getUTCDay();
          const operatingHour = operatingHours.find(oh => oh.day_of_week === dayOfWeek);

          if (!operatingHour || operatingHour.opens_at === undefined || operatingHour.closes_at === undefined) {
            return { error: 'O lava-rapido nao esta disponivel no dia selecionado.' };
          }

          const opensAtMinutes = operatingHour.opens_at;
          const closesAtMinutes = operatingHour.closes_at;
          const appointments = await fetchAppointments(selectedDate);

          let startMinutes = opensAtMinutes;
          if (isSameDay(date, new Date())) {
            const currentTimeMinutes = new Date().getHours() * 60 + new Date().getMinutes();
            startMinutes = currentTimeMinutes < opensAtMinutes ? opensAtMinutes : Math.ceil(currentTimeMinutes / 15) * 15;
          }

          const availableSlots = getAvailableSlots(startMinutes, closesAtMinutes, appointments, window.capacityPerSlot, 15, isSameDay(date, new Date()), startMinutes);
          return { availableSlots };
        }

      // Função para renderizar time slots
        function renderTimeSlots(slots) {
          const timeSlotsContainer = document.getElementById('time-slots');
          timeSlotsContainer.innerHTML = '';
          if (slots.length > 10) slots = slots.slice(0, 10);
          slots.forEach(slot => {
            const slotElement = document.createElement('div');
            slotElement.classList.add('time-slot');
            slotElement.dataset.start = slot.start;
            slotElement.textContent = `${slot.start} (${slot.capacity})`;
            slotElement.addEventListener('click', () => selectTimeSlot(slot.start, `${slot.start} (${slot.capacity})`));
            timeSlotsContainer.appendChild(slotElement);
          });
        }

      // Função para selecionar time slot
        function selectTimeSlot(startTime, displayText) {
          document.getElementById('appointment-time').value = startTime;
          document.getElementById('summary-time').textContent = displayText;
          document.querySelectorAll('.time-slot').forEach(slot => {
            slot.classList.toggle('selected', slot.dataset.start === startTime);
          });
        }

      // Função para obter slots disponíveis
        function getAvailableSlots(startMinutes, closesAtMinutes, appointments, capacityPerSlot, slotDuration, isToday, currentTimeMinutes) {
          const slots = [];
          let currentSlot = startMinutes;
          while (currentSlot < closesAtMinutes) {
            const slotEnd = currentSlot + slotDuration;
            if (slotEnd <= closesAtMinutes) {
              const capacity = capacityPerSlot - (appointments.filter(a => {
                const apptTime = timeToMinutes(a.start_time);
                return apptTime >= currentSlot && apptTime < slotEnd;
              }).length || 0);
              slots.push({ start: minutesToTime(currentSlot), capacity: capacity > 0 ? capacity : 0 });
            }
            currentSlot += slotDuration;
          }
          return slots.filter(slot => slot.capacity > 0 && (!isToday || currentSlot > currentTimeMinutes));
        }

      // Inicializar o formulário
        const loadingIndicator = document.getElementById('loading-indicator');
        const dateField = document.getElementById('appointment-date');
        const timeField = document.getElementById('appointment-time');
        const serviceField = document.getElementById('appointment-service');
        const submitButton = document.getElementById('submit-button');
        const summaryDate = document.getElementById('summary-date');
        const summaryTime = document.getElementById('summary-time');
        const summaryService = document.getElementById('summary-service');
        const summaryServicePrice = document.getElementById('summary-service-price');
        const summaryServiceFee = document.getElementById('summary-service-fee');
        const summaryTotal = document.getElementById('summary-total');
        const summaryRemaining = document.getElementById('summary-remaining');
        const form = document.getElementById('appointment-form');
        const cardErrors = document.getElementById('card-errors');
        const serviceFeeInput = document.getElementById('service-fee');
        const timeSlotsContainer = document.getElementById('time-slots');
        const cardElementContainer = document.getElementById('card-element');

        try {
          loadingIndicator.style.display = 'block';
          console.log("Indicador de carregamento exibido");

          let stripe;
          try {
            stripe = Stripe('<%= ENV["STRIPE_PUBLISHABLE_KEY"] %>');
            console.log("Stripe inicializado com sucesso via global");
          } catch (e) {
            console.error("Erro ao inicializar Stripe via global:", e);
            if (cardErrors) cardErrors.textContent = "Falha ao carregar Stripe. Verifique o console.";
            throw e;
          }

          if (cardElementContainer && stripe) {
            const elements = stripe.elements();
            cardElement = elements.create('card', {
              style: {
                base: {
                  color: '#FFFFFF',
                  fontFamily: 'Montserrat, sans-serif',
                  fontSize: '16px',
                  '::placeholder': { color: '#B3B3B3' },
                  backgroundColor: '#1c1c1c',
                  padding: '12px',
                  borderRadius: '8px',
                  iconColor: '#B3B3B3',
                  lineHeight: '24px'
                },
                invalid: {
                  color: '#EF4444',
                  iconColor: '#EF4444'
                }
              },
            });
            cardElement.mount('#card-element');
            console.log("Card Element montado com sucesso");
          } else {
            console.error("Container #card-element ou Stripe nao encontrado");
            if (cardErrors) cardErrors.textContent = "Erro ao carregar o campo do cartao.";
            throw new Error("Container #card-element ou Stripe nao encontrado");
          }

          loadingIndicator.style.display = 'none';
          dateField.disabled = false;
          serviceField.disabled = false;
          submitButton.disabled = false;
          console.log("Formulario habilitado");

          form.reset();
          if (cardElement) cardElement.clear();
          summaryDate.textContent = 'Nao selecionado';
          summaryTime.textContent = 'Nao selecionado';
          summaryService.textContent = 'Nao selecionado';
          summaryServicePrice.textContent = 'R$ 0,00';
          summaryServiceFee.textContent = 'R$ 0,00';
          summaryTotal.textContent = 'R$ 0,00';
          summaryRemaining.textContent = 'R$ 0,00';
          if (cardErrors) cardErrors.textContent = '';
          console.log("Formulario e resumo limpos");

          async function prepareTimePicker(selectedDate) {
            const date = getDateInSaoPauloTimezone(selectedDate);
            const dayOfWeek = date.getUTCDay();
            const operatingHour = window.operatingHours.find(oh => oh.day_of_week === dayOfWeek);

            if (!operatingHour || operatingHour.opens_at === undefined || operatingHour.closes_at === undefined) {
              return { error: 'O lava-rapido nao esta disponivel no dia selecionado.' };
            }

            const opensAtMinutes = operatingHour.opens_at;
            const closesAtMinutes = operatingHour.closes_at;
            const appointments = await fetchAppointments(selectedDate);

            let startMinutes = opensAtMinutes;
            if (isSameDay(date, new Date())) {
              const currentTimeMinutes = new Date().getHours() * 60 + new Date().getMinutes();
              startMinutes = currentTimeMinutes < opensAtMinutes ? opensAtMinutes : Math.ceil(currentTimeMinutes / 15) * 15;
            }

            const availableSlots = getAvailableSlots(startMinutes, closesAtMinutes, appointments, window.capacityPerSlot, 15, isSameDay(date, new Date()), startMinutes);
            return { availableSlots };
          }

          function renderTimeSlots(slots) {
            timeSlotsContainer.innerHTML = '';
            if (slots.length > 10) slots = slots.slice(0, 10);
            slots.forEach(slot => {
              const slotElement = document.createElement('div');
              slotElement.classList.add('time-slot');
              slotElement.dataset.start = slot.start;
              slotElement.textContent = `${slot.start} (${slot.capacity})`;
              slotElement.addEventListener('click', () => selectTimeSlot(slot.start, `${slot.start} (${slot.capacity})`));
              timeSlotsContainer.appendChild(slotElement);
            });
          }

          function selectTimeSlot(startTime, displayText) {
            timeField.value = startTime;
            summaryTime.textContent = displayText;
            document.querySelectorAll('.time-slot').forEach(slot => {
              slot.classList.toggle('selected', slot.dataset.start === startTime);
            });
          }

          serviceField.addEventListener('change', () => {
            const selectedOption = serviceField.options[serviceField.selectedIndex];
            const price = selectedOption.dataset.price || 0;
            const serviceFee = (price * 0.05).toFixed(2);
            const remaining = (price - serviceFee).toFixed(2);
            const total = parseFloat(serviceFee).toFixed(2);

            summaryService.textContent = selectedOption.text !== 'Selecione um servico' ? selectedOption.text : 'Nao selecionado';
            summaryServicePrice.textContent = `R$ ${parseFloat(price).toFixed(2)}`;
            summaryServiceFee.textContent = `R$ ${serviceFee}`;
            summaryTotal.textContent = `R$ ${total}`;
            summaryRemaining.textContent = `R$ ${remaining}`;
            serviceFeeInput.value = serviceFee;
          });

          if (cardElement) {
            cardElement.on('change', (event) => {
              if (event.error) {
                cardErrors.textContent = event.error.message;
              } else {
                cardErrors.textContent = '';
              }
            });
          }

          const handleSubmit = debounce(async () => {
            submitButton.disabled = true;
            submitButton.textContent = 'Processando...';

            const selectedTime = timeField.value;
            const selectedService = serviceField.value;

            try {
              if (!stripe || !cardElement) throw new Error("Stripe ou cardElement nao inicializado");
              const { paymentMethod, error } = await stripe.createPaymentMethod({ type: 'card', card: cardElement });
              if (error) {
                console.error('Erro ao criar PaymentMethod:', error);
                cardErrors.textContent = error.message;
                submitButton.disabled = false;
                submitButton.textContent = 'Confirmar Agendamento';
                return;
              }
              const formData = new FormData(form);
              formData.append('payment_method_id', paymentMethod.id);

              const response = await fetch(form.action, { method: 'POST', body: formData, headers: { 'Accept': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content } });
              if (!response.ok) throw new Error(await response.text());

              const result = await response.json();
              if (result.error) {
                cardErrors.textContent = result.error;
                submitButton.disabled = false;
                submitButton.textContent = 'Confirmar Agendamento';
                return;
              }

              if (result.requires_action) {
                const { paymentIntent, error: confirmError } = await stripe.handleCardAction(result.client_secret);
                if (confirmError) {
                  cardErrors.textContent = confirmError.message;
                  submitButton.disabled = false;
                  submitButton.textContent = 'Confirmar Agendamento';
                  return;
                }
                formData.delete('payment_method_id');
                formData.append('payment_intent_id', paymentIntent.id);
                const finalResponse = await fetch(form.action, { method: 'POST', body: formData, headers: { 'Accept': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content } });
                if (!finalResponse.ok) throw new Error(await finalResponse.text());
                const finalResult = await finalResponse.json();
                if (finalResult.success) window.location.href = finalResult.redirect_to;
              } else if (result.success) {
                window.location.href = result.redirect_to;
              }
            } catch (e) {
              console.error('Erro no frontend:', e);
              cardErrors.textContent = e.message.includes('Erro HTTP') ? e.message : 'Erro ao processar o pagamento: ' + e.message;
              submitButton.disabled = false;
              submitButton.textContent = 'Confirmar Agendamento';
            }
          }, 500);

          form.addEventListener('submit', (event) => {
            event.preventDefault();
            handleSubmit();
          });

          const sections = document.querySelectorAll('.fade-in-section');
          sections.forEach(section => { section.style.opacity = '1'; section.style.transform = 'translateY(0)'; });

          const controls = document.querySelectorAll('.form-control');
          controls.forEach(control => { control.style.opacity = '1'; control.style.transform = 'translateY(0)'; });

          const errors = document.querySelectorAll('.fade-in-error');
          errors.forEach(error => { error.style.opacity = '1'; error.style.transform = 'translateY(0)'; });
        } catch (e) {
          console.error('Erro geral:', e);
          const cardErrors = document.getElementById('card-errors');
          if (cardErrors) cardErrors.textContent = 'Erro ao carregar. Recarregue a pagina.';
          document.getElementById('loading-indicator').style.display = 'none';
        }
      });
}
};

// Função para obter slots disponíveis (fora do objeto para evitar escopo)
function getAvailableSlots(startMinutes, closesAtMinutes, appointments, capacityPerSlot, slotDuration, isToday, currentTimeMinutes) {
  const slots = [];
  let currentSlot = startMinutes;
  while (currentSlot < closesAtMinutes) {
    const slotEnd = currentSlot + slotDuration;
    if (slotEnd <= closesAtMinutes) {
      const capacity = capacityPerSlot - (appointments.filter(a => {
        const apptTime = timeToMinutes(a.start_time);
        return apptTime >= currentSlot && apptTime < slotEnd;
      }).length || 0);
      slots.push({ start: minutesToTime(currentSlot), capacity: capacity > 0 ? capacity : 0 });
    }
    currentSlot += slotDuration;
  }
  return slots.filter(slot => slot.capacity > 0 && (!isToday || currentSlot > currentTimeMinutes));
}
