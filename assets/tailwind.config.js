// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration
const plugin = require('tailwindcss/plugin');
const fs = require('node:fs');
const path = require('node:path');
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
    minWidth: {
      '0': '0',
      '1/4': '25%',
      '1/3': '33%',
      '1/2': '50%',
      '3/4': '75%',
      'full': '100%',
      'min': 'min-content',
      'max': 'max-content'
    },
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
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({ addVariant }) =>
      addVariant('phx-no-feedback', ['.phx-no-feedback&', '.phx-no-feedback &'])
    ),
    plugin(({ addVariant }) =>
      addVariant('phx-click-loading', [
        '.phx-click-loading&',
        '.phx-click-loading &',
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant('phx-submit-loading', [
        '.phx-submit-loading&',
        '.phx-submit-loading &',
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant('phx-change-loading', [
        '.phx-change-loading&',
        '.phx-change-loading &',
      ])
    ),
    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function({ matchComponents, theme }) {
      let iconsDir = path.join(__dirname, './vendor/heroicons/optimized');
      let values = {};
      let icons = [
        ['', '/24/outline'],
        ['-solid', '/24/solid'],
        ['-mini', '/20/solid'],
      ];
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).map(file => {
          let name = path.basename(file, '.svg') + suffix;
          values[name] = { name, fullPath: path.join(iconsDir, dir, file) };
        });
      });
      matchComponents(
        {
          hero: ({ name, fullPath }) => {
            let content = fs
              .readFileSync(fullPath)
              .toString()
              .replace(/\r?\n|\r/g, '');
            return {
              [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
              '-webkit-mask': `var(--hero-${name})`,
              mask: `var(--hero-${name})`,
              'mask-repeat': 'no-repeat',
              'background-color': 'currentColor',
              'vertical-align': 'middle',
              display: 'inline-block',
              width: theme('spacing.5'),
              height: theme('spacing.5'),
            };
          },
        },
        { values }
      );
    }),
    require('@tailwindcss/container-queries'),
  ],
};