// app/javascript/packs/application.js
import "../appointments.js";

document.addEventListener("DOMContentLoaded", () => {
  if (window.app && window.app.initAppointments) {
    window.app.initAppointments();
  }
});
