import path from 'node:path';
import esbuild from 'esbuild';
import { copy } from 'esbuild-plugin-copy';
import postcss from 'esbuild-postcss';

const ctx = await esbuild.context({
  // absWorkingDir: path.resolve('dev-server'),
  entryPoints: ['dev-server/src/index.tsx'],
  outdir: 'dev-server/dist/',
  bundle: true,
  splitting: true,
  sourcemap: true,
  format: 'esm',
  target: ['es2020'],
  tsconfig: 'tsconfig.browser.json',
  jsx: 'automatic',
  loader: {
    '.woff2': 'file',
    '.ttf': 'copy',
  },
  plugins: [
    postcss(),
    copy({
      assets: [
        {
          from: ['./dev-server/public/**/*'],
          to: ['.'],
        },
        {
          from: ['../priv/static/*'],
          to: ['.'],
        },
        {
          from: ['../priv/static/images/**/*'],
          to: ['./images'],
        },
      ],
    }),
  ],
});

await ctx.watch();

await ctx.serve({
  servedir: 'dev-server/dist',
  port: 3000,
});
