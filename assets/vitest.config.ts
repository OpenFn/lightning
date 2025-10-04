import path from "path";
import react from "@vitejs/plugin-react";
import tsconfigPaths from "vite-tsconfig-paths";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  test: {
    globals: true,
    environment: "jsdom",
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
