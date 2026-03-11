const path = require("path");

module.exports = {
  mode: "production",
  entry: "./app/javascript/application.js",
  output: {
    filename: "application.js",
    path: path.resolve(__dirname, "../public/packs")
  },
  resolve: {
    extensions: [".js"]
  },
  module: {
    rules: [
      {
        test: /\.js$/,
        use: {
          loader: "babel-loader",
          options: {
            presets: [
              [
                "@babel/preset-env",
                {
                  targets: {
                    node: "16.20.2"
                  },
                  useBuiltIns: "entry",
                  corejs: "3.30.2",
                  forceAllTransforms: true,
                  include: [
                    "transform-async-to-generator",
                    "transform-regenerator"
                  ]
                }
              ]
            ],
            plugins: [
              [
                "@babel/plugin-transform-runtime",
                {
                  corejs: false,
                  helpers: true,
                  regenerator: true,
                  useESModules: false,
                  absoluteRuntime: false
                }
              ]
            ],
            cacheDirectory: true,
            sourceMaps: true
          }
        }
      },
      {
        test: /\.css$/,
        use: ["style-loader", "css-loader"]
      }
    ]
  },
  devtool: "source-map"
};
