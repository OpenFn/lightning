const processOnly = new Set(["--loader=ts-node/esm"]);

export default {
  extensions: {
    js: true,
    ts: "module",
  },
  nodeArguments: ["--import=tsimp", "--no-warnings"],
  filterNodeArgumentsForWorkerThreads: argument => !processOnly.has(argument),
  files: ["test/**/*.test.ts"],
  environmentVariables: {
    TS_NODE_PROJECT: "tsconfig.test.json",
    TSIMP_DIAG: "ignore",
  },
};
