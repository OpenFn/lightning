// Super minimal array definition to support typings
export default `
  interface Array<T> {
    [n: number]: T;
  }

  // hack to remove undefined from code suggest
  // https://github.com/microsoft/monaco-editor/issues/2018
  declare module undefined 
`;
