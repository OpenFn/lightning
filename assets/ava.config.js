const processOnly = new Set(['--loader=ts-node/esm']);

export default {
  extensions: {
    js: true,
    ts: 'module',
  },
  nodeArguments: ['--loader=ts-node/esm', '--no-warnings'],
  filterNodeArgumentsForWorkerThreads: argument => !processOnly.has(argument),
  files: ['test/**/*test.ts'],
};
