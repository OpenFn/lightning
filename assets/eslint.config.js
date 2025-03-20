import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import globals from 'globals';
import jsPlugin from '@eslint/js';
import tsPlugin from 'typescript-eslint';
import reactPlugin from 'eslint-plugin-react';
import reactCompilerPlugin from 'eslint-plugin-react-compiler';
import reactHooksPlugin from 'eslint-plugin-react-hooks';
import jsxA11yPlugin from 'eslint-plugin-jsx-a11y';
import promisePlugin from 'eslint-plugin-promise';
import compatPlugin from 'eslint-plugin-compat';
import commentsPlugin from '@eslint-community/eslint-plugin-eslint-comments/configs';
import importPlugin from 'eslint-plugin-import';

const __dirname = dirname(fileURLToPath(import.meta.url));

const javascriptExtensions = ['js', 'jsx'];
const typescriptExtensions = ['ts', 'tsx'];
const jsxExtensions = ['jsx', 'tsx'];
const baseExtensions = [...javascriptExtensions, ...typescriptExtensions];

const commonJsExtensions = (
  /** @type readonly string[] */
  exts
) => exts.map(ext => `c${ext}`);
const esmExtensions = (
  /** @type readonly string[] */
  exts
) => exts.map(ext => `m${ext}`);

const allExtensions = [
  ...baseExtensions,
  ...commonJsExtensions(baseExtensions),
  ...esmExtensions(baseExtensions),
];

const commonJsFiles = commonJsExtensions(baseExtensions).map(
  ext => `**/*.${ext}`
);
const javascriptFiles = [
  ...javascriptExtensions,
  ...commonJsExtensions(javascriptExtensions),
  ...esmExtensions(javascriptExtensions),
].map(ext => `**/*.${ext}`);
const nodeFiles = allExtensions.map(ext => `*.${ext}`);
const browserFiles = allExtensions.flatMap(ext =>
  ['js', 'vendor', 'dev-server'].map(dir => `${dir}/**/*.${ext}`)
);
const reactFiles = [
  ...jsxExtensions,
  ...commonJsExtensions(jsxExtensions),
  ...esmExtensions(jsxExtensions),
].map(ext => `**/*.${ext}`);

/** @type import("eslint").Linter.Config[] */
export default [
  {
    ignores: ['vendor/'],
  },
  ...[
    jsPlugin.configs['recommended'],
    importPlugin.flatConfigs['recommended'],
    importPlugin.flatConfigs['typescript'],
    ...tsPlugin.configs['recommendedTypeChecked'],
  ].map(conf => ({
    files: nodeFiles,
    ...conf,
  })),
  ...[
    jsPlugin.configs['recommended'],
    importPlugin.flatConfigs['recommended'],
    importPlugin.flatConfigs['typescript'],
    ...tsPlugin.configs['strictTypeChecked'],
  ].map(conf => ({
    files: browserFiles,
    ...conf,
  })),
  {
    files: ['**/*.d.ts'],
    rules: {
      '@typescript-eslint/no-floating-promises': 'off',
    },
  },
  ...[
    importPlugin.flatConfigs['recommended'],
    tsPlugin.configs['disableTypeChecked'],
  ].map(conf => ({
    files: javascriptFiles,
    ...conf,
  })),
  {
    languageOptions: {
      globals: globals.builtin,
      parserOptions: {
        projectService: true,
        tsconfigRootDir: __dirname,
      },
    },
    settings: {
      'import/cache': {
        // If you never use `eslint_d` or `eslint-loader`, you may set the cache lifetime to Infinity and everything should be fine:
        // https://github.com/import-js/eslint-plugin-import/blob/main/README.md#importcache
        lifetime: Infinity,
      },
      'import/resolver': {
        typescript: {
          alwaysTryTypes: true, // always try to resolve types under `<root>@types` directory even it doesn't contain any source code, like `@types/unist`
          project: ['tsconfig.node.json', 'tsconfig.browser.json'],
        },
      },
    },
  },
  promisePlugin.configs['flat/recommended'],
  compatPlugin.configs['flat/recommended'],
  commentsPlugin['recommended'],
  {
    files: commonJsFiles,
    languageOptions: { globals: globals.commonjs },
  },
  {
    files: nodeFiles,
    languageOptions: {
      globals: globals.node,
    },
  },
  {
    files: browserFiles,
    languageOptions: { globals: globals.browser },
  },
  {
    files: reactFiles,
    ...reactPlugin.configs.flat['recommended'],
    settings: { react: { version: 'detect' } },
    rules: {
      'react/prop-types': 'off',
    },
  },
  {
    files: reactFiles,
    ...reactPlugin.configs.flat['jsx-runtime'],
  },
  {
    files: reactFiles,
    ...reactHooksPlugin.configs['recommended-latest'],
  },
  {
    files: reactFiles,
    ...reactCompilerPlugin.configs['recommended'],
  },
  {
    files: reactFiles,
    ...jsxA11yPlugin.flatConfigs['strict'],
  },
];
