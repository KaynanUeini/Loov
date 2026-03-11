source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '~> 3.2.2'

gem 'rails', '~> 7.1.5.1'
gem 'pg', '~> 1.5'
gem 'puma', '~> 6.4.2' # Atualizado para a última versão estável
gem 'importmap-rails'
gem 'turbo-rails'
gem 'stimulus-rails'
gem 'jbuilder'
gem 'redis', '~> 5.0'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]
gem 'bootsnap', require: false
gem 'devise', '~> 4.9'
gem 'stripe', '~> 10.0'
gem 'sidekiq', '~> 7.2'
gem 'pundit', '~> 2.3'
gem 'sprockets-rails', '~> 3.5'
gem 'sassc-rails' # Adicionado para suporte a SCSS
gem 'geocoder'
gem 'dotenv-rails', groups: [:development, :test]
gem 'rails-i18n', '~> 7.0' # Use a versão compatível com sua versão do Rails
group :development, :test do
  gem 'debug', platforms: %i[mri mingw x64_mingw]
end

group :development do
  gem 'web-console'
  gem 'letter_opener', '~> 1.10' # Para visualizar emails no navegador
  gem 'bullet', '~> 7.2' # Para detectar problemas de performance (N+1 queries)
end

group :test do
  gem 'capybara'
  gem 'selenium-webdriver'
end


gem "faker", "~> 3.6"
