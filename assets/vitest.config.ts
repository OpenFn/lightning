import path from "path";
import tsconfigPaths from "vite-tsconfig-paths";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [tsconfigPaths()],
  test: {
    globals: true,
    environment: "node",
    setupFiles: ["./test/_setup.ts"],
    include: ["test/**/*.test.ts", "test/**/*.test.tsx"],
    exclude: ["node_modules/**/*"],
    reporters: ["verbose", "junit"],
    outputFile: {
      junit: "../test/reports/vitest.xml",
    },
    // Suppress debug logs during tests (matches current setup)
    silent: false,
    logHeapUsage: true,
  },
  resolve: {
    alias: {
      // Ensure path aliases are resolved correctly
      "#": path.resolve(__dirname, "./js"),
    },
  },
});
