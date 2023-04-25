import liveserver from 'live-server'; // dev server
import esbuild from 'esbuild';
import { copy } from 'esbuild-plugin-copy';
import postcss from 'esbuild-postcss';

liveserver.start({
  port: 3000, // Set the server port. Defaults to 8080.
  root: 'dist', // Set root directory that's being served. Defaults to cwd.
  open: false, // When false, it won't load your browser by default.
  wait: 500, // Waits for all changes, before reloading. Defaults to 0 sec.
  logLevel: 2, // 0 = errors only, 1 = some, 2 = lots
  ignore: 'node_modules/**/src',
});

// await esbuild.build({
//   entryPoints: ['src/react.tsx'],
//   outdir: 'dist/',
//   bundle: true,
//   format: 'esm',
//   target: ['es2020'],
// });

// Main application source with react externalised
await esbuild.build({
  entryPoints: ['src/index.tsx'],
  outdir: 'dist/',
  bundle: true,
  splitting: true,
  sourcemap: true,
  watch: true,
  format: 'esm',
  target: ['es2020'],
  // external: ['react', 'react-dom'],
  plugins: [
    postcss(),
    copy({
      assets: {
        from: ['./public/*'],
        to: ['.'],
      },
    }),
  ],
});
