/**
 * Monaco Editor Mock for Tests
 *
 * This mock replaces the full monaco-editor package (8MB+) to prevent
 * test timeouts and Vite resolution issues.
 */

export const editor = {
  createDiffEditor: () => ({
    setModel: () => {},
    dispose: () => {},
    getModel: () => ({
      original: { dispose: () => {} },
      modified: { dispose: () => {} },
    }),
  }),
  createModel: (code: string) => ({
    code,
    dispose: () => {},
  }),
  setModelLanguage: () => {},
};

export const languages = {
  typescript: {
    javascriptDefaults: {
      setCompilerOptions: () => {},
      setDiagnosticsOptions: () => {},
      setEagerModelSync: () => {},
      addExtraLib: () => ({ dispose: () => {} }),
      setExtraLibs: () => {},
    },
    typescriptDefaults: {
      setCompilerOptions: () => {},
      setDiagnosticsOptions: () => {},
      setEagerModelSync: () => {},
      addExtraLib: () => ({ dispose: () => {} }),
      setExtraLibs: () => {},
    },
  },
  registerCompletionItemProvider: () => ({ dispose: () => {} }),
};

export const KeyMod = {
  CtrlCmd: 1,
  Shift: 2,
  Alt: 4,
  WinCtrl: 8,
};

export const KeyCode = {
  Enter: 13,
  Escape: 27,
  Space: 32,
  Tab: 9,
};

// Export as default and named exports to match monaco-editor package
export default {
  editor,
  languages,
  KeyMod,
  KeyCode,
};
