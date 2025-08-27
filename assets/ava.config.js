export default {
  extensions: {
    js: true,
    ts: "module",
  },
  nodeArguments: ["--import=tsimp", "--no-warnings"],
  files: ["test/**/*.test.ts"],
  environmentVariables: {
    TS_NODE_PROJECT: "tsconfig.test.json",
    TSIMP_DIAG: "ignore",
  },
  watchMode: {
    ignoreChanges: [".tsimp/**/*"],
  },
};
