import { withThemeByClassName } from '@storybook/addon-themes';

import type { Preview } from '@storybook/react-vite';

// Fonts and the full application design system (Tailwind theme tokens, custom
// utilities, heroicons/lucide masks, xyflow + monaco styles). See
// `.storybook/main.ts` for how the Elixir-only petal import is stripped.
import '../fonts/inter.css';
import '../fonts/fira-code.css';
import '../css/app.css';

const preview: Preview = {
  parameters: {
    layout: 'centered',
    controls: {
      matchers: {
        color: /(background|color)$/i,
        date: /Date$/i,
      },
    },
    options: {
      storySort: {
        order: [
          'Introduction',
          'Foundations',
          ['Colors', 'Typography', 'Icons'],
          'Components',
          'LiveView Clones',
          '*',
        ],
      },
    },
    a11y: {
      // Surface accessibility findings without failing the build.
      test: 'todo',
    },
  },
  decorators: [
    withThemeByClassName({
      themes: {
        Light: '',
        Dark: 'dark',
      },
      defaultTheme: 'Light',
    }),
  ],
};

export default preview;
