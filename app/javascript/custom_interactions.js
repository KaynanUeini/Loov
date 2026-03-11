document.addEventListener('DOMContentLoaded', function() {
  // Modo Claro/Escuro
  const themeToggle = document.querySelector('.theme-toggle');
  if (themeToggle) {
    themeToggle.addEventListener('click', function() {
      document.body.classList.toggle('light-mode');
      localStorage.setItem('theme', document.body.classList.contains('light-mode') ? 'light' : 'dark');
    });

    // Carregar o tema salvo
    const savedTheme = localStorage.getItem('theme');
    if (savedTheme === 'light') {
      document.body.classList.add('light-mode');
    }
  }

  // Botão Voltar ao Topo
  const backToTop = document.createElement('button');
  backToTop.classList.add('back-to-top');
  backToTop.innerHTML = `
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
      <path d="M12 5l-7 7h5v7h4v-7h5l-7-7z"/>
    </svg>
  `;
  document.body.appendChild(backToTop);

  window.addEventListener('scroll', function() {
    if (window.scrollY > 300) {
      backToTop.classList.add('visible');
    } else {
      backToTop.classList.remove('visible');
    }
  });

  backToTop.addEventListener('click', function() {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  });

  // Efeito de Tilt nos Cards
  const cards = document.querySelectorAll('.card');
  cards.forEach(card => {
    card.addEventListener('mousemove', function(e) {
      const rect = card.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      const centerX = rect.width / 2;
      const centerY = rect.height / 2;
      const rotateX = (y - centerY) / 20;
      const rotateY = (centerX - x) / 20;

      card.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) scale(1.02)`;
    });

    card.addEventListener('mouseleave', function() {
      card.style.transform = 'perspective(1000px) rotateX(0) rotateY(0) scale(1)';
    });
  });

  // Efeito Parallax
  const parallaxBg = document.createElement('div');
  parallaxBg.classList.add('parallax-bg');
  document.body.appendChild(parallaxBg);

  window.addEventListener('scroll', function() {
    const scrollPosition = window.scrollY;
    parallaxBg.style.transform = `translateY(${scrollPosition * 0.5}px)`;
  });
});
