import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import tailwindcss from '@tailwindcss/vite';

import type { StorybookConfig } from '@storybook/react-vite';
import type { Plugin } from 'vite';

const here = dirname(fileURLToPath(import.meta.url));

/**
 * `css/app.css` ends with an `@import` of the compiled petal_components
 * stylesheet, which lives under `deps/` and only exists once the Elixir
 * dependencies have been fetched. Storybook builds the design system with Vite
 * alone (no Elixir toolchain), so we strip that single import here. Everything
 * else — the Tailwind theme tokens, custom utilities and animations — is shared
 * verbatim with the running app, which keeps Storybook in sync automatically.
 */
function stripElixirOnlyCss(): Plugin {
  return {
    name: 'lightning-storybook-strip-elixir-css',
    enforce: 'pre',
    transform(code, id) {
      if (id.includes('/css/app.css')) {
        return {
          code: code.replace(
            /@import\s+['"][^'"]*petal_components[^'"]*['"];?/g,
            ''
          ),
          map: null,
        };
      }
      return null;
    },
  };
}

const config: StorybookConfig = {
  stories: ['../js/**/*.mdx', '../js/**/*.stories.@(js|jsx|ts|tsx)'],
  addons: [
    '@storybook/addon-docs',
    '@storybook/addon-a11y',
    '@storybook/addon-themes',
  ],
  framework: {
    name: '@storybook/react-vite',
    options: {},
  },
  core: {
    disableTelemetry: true,
  },
  async viteFinal(viteConfig) {
    const { mergeConfig } = await import('vite');

    return mergeConfig(viteConfig, {
      plugins: [stripElixirOnlyCss(), tailwindcss()],
      // The repo ships a `.postcssrc` that registers `tailwindcss` as a classic
      // PostCSS plugin (used by the standalone Tailwind CLI build). Tailwind v4
      // no longer works that way, and here `@tailwindcss/vite` owns the Tailwind
      // pipeline, so we pin an empty inline PostCSS config to stop Vite from
      // discovering and applying that file.
      css: {
        postcss: { plugins: [] },
      },
      // Mirror the esbuild `--define:ENABLE_DEVTOOLS` flag from
      // config/config.exs so components that reference the global compile.
      define: {
        ENABLE_DEVTOOLS: 'false',
      },
      resolve: {
        // Mirror the `#/*` -> `js/*` path alias from tsconfig.base.json.
        alias: {
          '#': resolve(here, '../js'),
        },
      },
    });
  },
};

export default config;
