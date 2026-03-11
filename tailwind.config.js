/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/views/**/*.{erb,html}',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/assets/javascripts/**/*.js',
  ],
  theme: {
    extend: {},
  },
  plugins: [
    require('daisyui')
  ],
}
