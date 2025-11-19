import type { editor } from 'monaco-editor';

import type { Monaco } from './index';

/**
 * Adds keyboard shortcut overrides to Monaco Editor to allow external handlers
 * (like KeyboardProvider) to receive Cmd/Ctrl+Enter events.
 *
 * By default, Monaco Editor intercepts certain keyboard shortcuts (like Cmd+Enter)
 * for its own command system. This function overrides those shortcuts to dispatch
 * synthetic KeyboardEvents to the window, allowing your application's keyboard
 * handler system to process them instead.
 *
 * Overridden shortcuts:
 * - Cmd/Ctrl+Enter: Dispatches to window for run/retry actions
 * - Cmd/Ctrl+Shift+Enter: Dispatches to window for force-run actions
 *
 * Usage:
 * ```typescript
 * <MonacoEditor
 *   onMount={(editor, monaco) => {
 *     addKeyboardShortcutOverrides(editor, monaco);
 *   }}
 * />
 * ```
 *
 * @param editor - Monaco editor instance
 * @param monaco - Monaco API object
 */
export function addKeyboardShortcutOverrides(
  editor: editor.IStandaloneCodeEditor,
  monaco: Monaco
): void {
  // Override Monaco's Cmd/Ctrl+Enter
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter, () => {
    const event = new KeyboardEvent('keydown', {
      key: 'Enter',
      code: 'Enter',
      metaKey: true,
      ctrlKey: true,
      bubbles: true,
      cancelable: true,
    });
    window.dispatchEvent(event);
  });

  // Override Monaco's Cmd/Ctrl+Shift+Enter
  editor.addCommand(
    monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.Enter,
    () => {
      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        code: 'Enter',
        metaKey: true,
        ctrlKey: true,
        shiftKey: true,
        bubbles: true,
        cancelable: true,
      });
      window.dispatchEvent(event);
    }
  );
}
