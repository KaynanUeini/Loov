# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
Rails.application.config.assets.paths << Rails.root.join('app', 'assets', 'stylesheets')
Rails.application.config.assets.paths << Rails.root.join('app', 'assets', 'images')
Rails.application.config.assets.paths << Rails.root.join('app', 'javascript')
Rails.application.config.assets.paths << Rails.root.join('vendor', 'javascript')

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in app/assets folder are already added.
Rails.application.config.assets.precompile += %w( tailwind.css custom.css *.png *.jpg *.jpeg *.gif )

# Enable dynamic compilation in development
Rails.application.config.assets.compile = true
