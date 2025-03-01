import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import globals from 'globals';
import eslint from '@eslint/js';
import tseslint from 'typescript-eslint';
import react from 'eslint-plugin-react';
// @ts-expect-error -- no typedefs available
import reactCompiler from 'eslint-plugin-react-compiler';
import reactHooks from 'eslint-plugin-react-hooks';
// @ts-expect-error -- no typedefs available
import jsxA11y from 'eslint-plugin-jsx-a11y';

const __dirname = dirname(fileURLToPath(import.meta.url));

const baseExtensions = ['js', 'ts', 'jsx', 'tsx'];

const commonJsExtensions = baseExtensions.map(ext => `c${ext}`);
const esmExtensions = baseExtensions.map(ext => `m${ext}`);

const extensions = [...baseExtensions, ...commonJsExtensions, ...esmExtensions];

const nodeFiles = { files: [`./*.${extensions.join(',')}`] };

const browserFiles = {
  files: [`./{js,vendor,dev-server}/**/*.${extensions.join(',')}`],
};

export default tseslint.config(
  eslint.configs.recommended,
  {
    languageOptions: {
      globals: globals.builtin,
      parserOptions: {
        projectService: true,
        tsconfigRootDir: __dirname,
      },
    },
  },
  tseslint.configs.strictTypeChecked.map(config => ({
    ...browserFiles,
    ...config,
  })),
  tseslint.configs.recommendedTypeChecked.map(config => ({
    ...nodeFiles,
    ...config,
  })),
  {
    files: [`./**/*.${commonJsExtensions.join(',')}`],
    languageOptions: { globals: globals.commonjs },
  },
  {
    ...nodeFiles,
    languageOptions: {
      globals: {
        ...globals.nodeBuiltin,
        ...globals.node,
      },
    },
  },
  {
    ...browserFiles,
    languageOptions: { globals: globals.browser },
  },
  {
    ...browserFiles,
    ...react.configs.flat['recommended'],
    settings: { react: { version: 'detect' } },
  },
  {
    ...browserFiles,
    ...react.configs.flat['jsx-runtime'],
  },
  {
    ...browserFiles,
    ...reactHooks.configs['recommended-latest'],
  },
  {
    ...browserFiles,
    ...reactCompiler.configs['recommended'],
  },
  {
    ...browserFiles,
    ...jsxA11y.flatConfigs['strict'],
  }
);
