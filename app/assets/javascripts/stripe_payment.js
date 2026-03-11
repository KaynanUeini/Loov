//= require ./stripe_payment

(function() {
  this.StripePayment = class {
    static init(stripe, elements, cardElement) {
      console.log("StripePayment initialized");
      cardElement.on('change', (event) => {
        if (event.error) {
          document.getElementById('card-errors').textContent = event.error.message;
        } else {
          document.getElementById('card-errors').textContent = '';
        }
      });
    }
  };

  document.addEventListener("turbo:load", function() {
    const stripe = Stripe('<%= ENV["STRIPE_PUBLISHABLE_KEY"] %>');
    const elements = stripe.elements();
    const cardElement = elements.create('card', {
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
          lineHeight: '24px',
        },
        invalid: { color: '#EF4444', iconColor: '#EF4444' },
      },
    });
    cardElement.mount('#card-element');
    StripePayment.init(stripe, elements, cardElement);
  });
}).call(this);
