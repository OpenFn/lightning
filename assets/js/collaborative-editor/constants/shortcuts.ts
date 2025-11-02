/**
 * Keyboard shortcut scopes for the collaborative editor
 *
 * Scopes allow different parts of the UI to have isolated keyboard shortcuts.
 * When a scope is enabled, shortcuts in that scope take priority.
 */
export const SHORTCUT_SCOPES = {
  /** Full-screen IDE editor scope */
  IDE: "ide",
  /** Manual run panel scope (when panel is open in WorkflowEditor) */
  RUN_PANEL: "runpanel",
  /** Inspector panel scope */
  PANEL: "panel",
} as const;

export type ShortcutScope =
  (typeof SHORTCUT_SCOPES)[keyof typeof SHORTCUT_SCOPES];
