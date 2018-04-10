const webpack = require('webpack');
const path = require('path');
const MiniCssExtractPlugin = require("mini-css-extract-plugin");
const HtmlWebpackPlugin = require('html-webpack-plugin');
const CopyWebpackPlugin = require('copy-webpack-plugin');
const ZipPlugin = require('zip-webpack-plugin');
const LiveReloadPlugin = require('webpack-livereload-plugin');
const UglifyJSPlugin = require('uglifyjs-webpack-plugin');
const OptimizeCssAssetsPlugin = require('optimize-css-assets-webpack-plugin');

/**
 * Configuration valid both for development and production environments.
 */
const common = {
    entry: {
        index: './src/index.js'
    },
    module: {
        rules: [
            {
                test: /\.js$/,
                exclude: /node_modules/,
                loader: 'babel-loader',

                options: {
                    presets: [
                        ["env", {
                            "targets": {
                                "browsers": ["last 2 versions", "safari >= 7"]
                            }
                        }]
                    ]
                }
            },
            {
                test: /\.elm$/,
                exclude: [/elm-stuff/, /node_modules/],
                loader: 'elm-webpack-loader'
            }
        ]
    },
    plugins: [
        new HtmlWebpackPlugin({
            title: 'Phoenix Chrome plug-in'
        }),
        new CopyWebpackPlugin([
            {from: 'chrome-ext/'}
        ])
    ]
};

/**
 * Overrides/additions for development environment.
 */
const dev = {
    output: {
        path: path.resolve(__dirname, 'build/dev'),
        filename: '[name].js'
    },
    module: {
        rules: [
            {
                test: /\.(scss|css)$/,
                use: [
                    'style-loader',
                    'css-loader',
                    'sass-loader'
                ]
            }
        ]
    },
    plugins: [
        new LiveReloadPlugin({appendScriptTag: true, protocol: 'http', hostname: 'localhost'})
    ]
};

/**
 * Overrides/additions for production environment.
 */
const prod = {
    output: {
        path: path.resolve(__dirname, 'build/chrome-ext'),
        filename: '[hash].js'
    },
    module: {
      rules: [
          {
              test: /\.(scss|css)$/,
              use: [
                  MiniCssExtractPlugin.loader,
                  'css-loader',
                  'sass-loader'
              ]
          }
      ]
    },
    plugins: [
        new MiniCssExtractPlugin({
            filename: "[hash].css",
        }),
        new UglifyJSPlugin(),
        new OptimizeCssAssetsPlugin(),
        new webpack.DefinePlugin({
            'process.env.NODE_ENV': JSON.stringify('production')
        }),
        new ZipPlugin({
            filename: 'chrome-ext.zip'
        })
    ]
};

/**
 * Exports a function building resulting configuration.
 */
module.exports = () => {
    const buildingForProd = (function () {
        const m = process.argv.indexOf('--mode');
        return m >= 0 && m < process.argv.length - 1 && process.argv[m + 1] === 'production';
    })();

    const merge = require('webpack-merge');
    if (buildingForProd) {
        return merge(common, prod);
    }

    return merge(common, dev);
};
