// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration
const defaultTheme = require('tailwindcss/defaultTheme');
const colors = require('tailwindcss/colors');

module.exports = {
  darkMode: 'class',
  content: [
    './js/**/*.{js,jsx,ts,tsx}',
    './node_modules/@openfn/**/*.{js,jsx,ts,tsx,css}',
    '../lib/*_web.ex',
    '../lib/*_web/**/*.*ex',
    '../deps/petal_components/**/*.*ex',
  ],
  theme: {
    extend: {
      colors: {
        primary: colors.indigo,
        secondary: colors.gray,
        success: colors.green,
        danger: colors.red,
        warning: colors.yellow,
        info: colors.sky,
        gray: colors.gray,
      },
      fontFamily: {
        sans: ['Inter var', ...defaultTheme.fontFamily.sans],
        mono: ['Fira Code VF', ...defaultTheme.fontFamily.mono],
      },
      animation: {
        'spin-pause': 'spin-pause 2s infinite ease',
        'fill-up': 'fill-up 2s infinite ease-in',
      },
      keyframes: {
        'spin-pause': {
          '0%': { transform: 'rotate(0deg)' },
          '25%': { transform: 'rotate(180deg)' },
          '50%': { transform: 'rotate(180deg)' },
          '75%': { transform: 'rotate(360deg)' },
          '100%': { transform: 'rotate(360deg)' },
        },
        'fill-up': {
          '0%': { height: '0%' },
          '25%': { height: '0%' },
          '50%': { height: '100%' },
          '75%': { height: '100%' },
          '100%': { height: '0%' },
        },
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/container-queries'),
  ],
};
