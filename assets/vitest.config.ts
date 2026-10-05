import path from 'path';

import react from '@vitejs/plugin-react';
import tsconfigPaths from 'vite-tsconfig-paths';
import { defineConfig } from 'vitest/config';

// Number and date formatting in the app uses the viewer's own locale (bare
// `toLocaleString()`), which is correct for users but makes any test asserting a
// formatted literal depend on the developer's `LANG`. Pin one locale for the run
// so the suite is deterministic; set here rather than in the npm scripts so a
// bare `npx vitest` behaves the same. Must be set before the worker processes
// fork, since Node resolves its default locale at startup.
process.env.LC_ALL = 'en_US.UTF-8';

export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  define: {
    // Match esbuild define from config/config.exs
    // Disable DevTools in tests to avoid overhead
    ENABLE_DEVTOOLS: false,
  },
  test: {
    // Use forks (child_process) instead of default threads (worker_threads)
    // to prevent hanging processes when test output is piped to head/tail.
    // Worker threads can't handle SIGPIPE, so they keep running after pipes
    // break. Can revert to "threads" if Node.js fixes worker_threads SIGPIPE.
    pool: 'forks',
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./test/_setup.ts'],
    include: ['test/**/*.test.ts', 'test/**/*.test.tsx'],
    exclude: ['node_modules/**/*'],
    reporters: ['verbose', 'junit'],
    outputFile: {
      junit: '../test/reports/vitest.xml',
    },
    // Suppress debug logs during tests (matches current setup)
    silent: false,
    logHeapUsage: true,
    server: {
      deps: {
        // Don't try to optimize monaco-editor (it's mocked in tests)
        inline: ['monaco-editor'],
      },
    },
  },
  resolve: {
    alias: {
      // Ensure path aliases are resolved correctly
      '#': path.resolve(__dirname, './js'),
      // morphdom is needed by phoenix_live_view internals (dom_patch.js)
      // but the deps/ folder can't resolve from our node_modules
      morphdom: path.resolve(__dirname, './node_modules/morphdom'),
      // Mock monaco-editor for tests (8MB+ package causes issues)
      'monaco-editor': path.resolve(
        __dirname,
        './test/__mocks__/monaco-editor.ts'
      ),
    },
  },
});
