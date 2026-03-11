const { environment } = require('@rails/webpacker')

// Remover plugins ou configurações que causem conflito com Turbo
const customConfig = {
  resolve: {
    extensions: ['.js', '.jsx', '.css', '.png', '.jpg', '.jpeg', '.gif'] // Suporte a imagens
  },
  module: {
    rules: [
      {
        test: /\.(png|jpg|jpeg|gif)$/i,
        use: [
          {
            loader: 'file-loader',
            options: {
              name: 'images/[name]-[hash].[ext]',
              publicPath: '/assets/'
            }
          }
        ]
      }
    ]
  }
}

environment.config.merge(customConfig)

// Desativar configurações obsoletas que causam erro com Turbo
environment.loaders.delete('nodeModules')

module.exports = environment
