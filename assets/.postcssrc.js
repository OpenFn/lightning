const path = require('path');

module.exports = {
  plugins: {
    'postcss-import': {
      path: [path.join(__dirname, '../assets/css')],
    },
    tailwindcss: {},
    autoprefixer: {},
  },
};
