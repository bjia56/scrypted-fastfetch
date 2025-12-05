const path = require('path');
const NodePolyfillPlugin = require('node-polyfill-webpack-plugin');

module.exports = {
  entry: './src/x-fastfetch.coffee',
  output: {
    filename: 'x-fastfetch.js',
    path: path.resolve(__dirname, '..', '..', 'fs', 'dist'),
    library: {
      type: 'module',
    },
    clean: true,
  },
  experiments: {
    outputModule: true,
  },
  resolve: {
    extensions: ['.coffee', '.js', '.ts'],
  },
  module: {
    rules: [
      {
        test: /\.coffee$/,
        use: 'coffee-loader',
      },
      {
        test: /\.ts$/,
        use: {
          loader: 'ts-loader',
          options: {
            transpileOnly: true,
          },
        },
      },
      {
        test: /\.css$/,
        oneOf: [
          {
            resourceQuery: /raw/,
            type: 'asset/source',
          },
          {
            use: ['css-loader'],
          },
        ],
      },
    ],
  },
  plugins: [
    new NodePolyfillPlugin(),
  ],
  devtool: 'source-map',
};
