import path from 'path';

import react from '@vitejs/plugin-react';
import tsconfigPaths from 'vite-tsconfig-paths';
import { defineConfig } from 'vitest/config';

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
  },
  resolve: {
    alias: {
      // Ensure path aliases are resolved correctly
      '#': path.resolve(__dirname, './js'),
    },
  },
});
