/**
 * Keyboard hotkey scopes for the collaborative editor
 *
 * Scopes allow different parts of the UI to have isolated keyboard shortcuts.
 * When a scope is enabled, shortcuts in that scope take priority.
 */
export const HOTKEY_SCOPES = {
  /** Full-screen IDE editor scope */
  IDE: 'ide',
  /** Manual run panel scope (when panel is open in WorkflowEditor) */
  RUN_PANEL: 'runpanel',
  /** Inspector panel scope */
  PANEL: 'panel',
  /** Modal dialog scope (when any modal is open) */
  MODAL: 'modal',
} as const;

export type HotkeyScope = (typeof HOTKEY_SCOPES)[keyof typeof HOTKEY_SCOPES];
