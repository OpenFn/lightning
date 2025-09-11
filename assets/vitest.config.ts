import { defineConfig } from 'vitest/config'
import tsconfigPaths from 'vite-tsconfig-paths'
import path from 'path'

export default defineConfig({
  plugins: [tsconfigPaths()],
  test: {
    globals: true,
    environment: 'node',
    setupFiles: ['./test/_setup.ts'],
    include: ['test/**/*.test.ts'],
    exclude: ['node_modules/**/*'],
    reporter: ['verbose', 'junit'],
    outputFile: {
      junit: '../test/reports/vitest.xml'
    },
    // Suppress debug logs during tests (matches current setup)
    silent: false,
    logHeapUsage: true
  },
  resolve: {
    alias: {
      // Ensure path aliases are resolved correctly
      '#': path.resolve(__dirname, './js')
    }
  }
})