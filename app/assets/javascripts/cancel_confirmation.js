console.log("cancel_confirmation.js loaded");

document.addEventListener('DOMContentLoaded', function() {
  console.log("DOMContentLoaded event fired (cancel_confirmation.js)");

  // Seleciona todos os botões de cancelamento
  const cancelButtons = document.querySelectorAll('.cancel-button');
  console.log("Cancel buttons found:", cancelButtons.length);

  cancelButtons.forEach(button => {
    console.log("Adding click event listener to cancel button:", button);
    // Remove qualquer evento de clique existente para evitar duplicatas
    button.removeEventListener('click', handleCancelClick);
    button.addEventListener('click', handleCancelClick);
  });
});

function handleCancelClick(event) {
  console.log("Cancel button clicked:", event.target);
  event.preventDefault(); // Impede o envio imediato do formulário

  // Obtém os dados do agendamento a partir dos atributos data
  const date = event.target.getAttribute('data-date');
  const time = event.target.getAttribute('data-time');
  const scheduledAt = parseInt(event.target.getAttribute('data-scheduled-at')); // Horário do agendamento em milissegundos
  const carWash = event.target.getAttribute('data-car-wash');
  console.log("Confirmation data:", { date, time, scheduledAt, carWash });

  // Verifica se o agendamento está a menos de 2 horas do horário atual
  const currentTime = new Date().getTime(); // Horário atual em milissegundos
  const twoHoursInMillis = 2 * 60 * 60 * 1000; // 2 horas em milissegundos
  const timeDifference = scheduledAt - currentTime;
  console.log("Time difference (ms):", timeDifference);

  if (timeDifference < twoHoursInMillis) {
    console.log("Cannot cancel: Less than 2 hours until scheduled time");
    alert("Você só pode cancelar agendaments com pelo menos 2 horas de antecedência.");
    return; // Impede a mensagem de confirmação e o envio do formulário
  }

  // Cria a mensagem de confirmação personalizada
  const confirmationMessage = `Você realmente deseja cancelar o agendamento no dia ${date} às ${time} no lava-rápido ${carWash}? Essa ação não pode ser desfeita.`;
  console.log("Confirmation message:", confirmationMessage);

  // Exibe a mensagem de confirmação e prossegue se o usuário confirmar
  if (confirm(confirmationMessage)) {
    console.log("User confirmed cancellation, submitting form...");
    event.target.closest('form').submit(); // Envia o formulário se confirmado
  } else {
    console.log("User cancelled the cancellation.");
  }
}
