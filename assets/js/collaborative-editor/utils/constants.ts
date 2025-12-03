/**
 * Application constants for the collaborative editor
 */

export const GITHUB_BASE_URL = 'https://github.com';

/**
 * Z-index layer system for UI components.
 *
 * Ensures consistent layering across the collaborative editor.
 * Higher numbers appear above lower numbers.
 */
export const Z_INDEX = {
  /** Template details card overlay on canvas */
  TEMPLATE_DETAILS_CARD: 5,
  /** Inspector panel on the right side */
  INSPECTOR: 10,
  /** Manual run panel */
  RUN_PANEL: 20,
  /** Side panels (Create Workflow, AI Assistant) */
  SIDE_PANEL: 60,
  /** Toggle button for collapsed side panels */
  SIDE_PANEL_TOGGLE: 61,
} as const;

/**
 * Resizable panel constraints.
 *
 * Used by useResizablePanel hook to enforce consistent sizing across
 * all resizable panels (left panel, AI assistant panel).
 */
export const PANEL_CONSTRAINTS = {
  /** Minimum panel width in pixels */
  MIN_WIDTH_PIXELS: 300,
  /** Maximum panel width in pixels */
  MAX_WIDTH_PIXELS: 600,
  /** Minimum panel width as percentage of viewport (0-1) */
  MIN_WIDTH_PERCENT: 0.2,
  /** Maximum panel width as percentage of viewport (0-1) */
  MAX_WIDTH_PERCENT: 0.4,
} as const;
