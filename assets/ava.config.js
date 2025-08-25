const processOnly = new Set(['--loader=ts-node/esm']);

export default {
  extensions: {
    js: true,
    ts: 'module',
  },
  nodeOptions: ['--loader=ts-node/esm', '--no-warnings'],
  filterNodeArgumentsForWorkerThreads: argument => !processOnly.has(argument),
  files: ['test/**/*.test.ts'],
  environmentVariables: {
    TS_NODE_PROJECT: 'tsconfig.test.json'
  }
};
