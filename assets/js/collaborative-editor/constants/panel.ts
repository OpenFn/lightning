/**
 * Render modes for ManualRunPanel
 *
 * Controls styling and behavior differences between standalone and embedded contexts.
 */
export const RENDER_MODES = {
  /** Standalone mode - panel is the main UI element (WorkflowEditor) */
  STANDALONE: 'standalone',
  /** Embedded mode - panel is embedded within another UI (FullScreenIDE) */
  EMBEDDED: 'embedded',
} as const;

export type RenderMode = (typeof RENDER_MODES)[keyof typeof RENDER_MODES];
