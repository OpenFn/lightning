/**
 * UI type definitions
 *
 * Defines the shape of transient UI state like panel visibility
 * and context for the collaborative editor.
 */

// =============================================================================
// TYPESCRIPT TYPES
// =============================================================================

/**
 * UI store state for transient UI concerns like panel visibility
 */
export interface UIState {
  runPanelOpen: boolean;

  /** Context for run panel (which job/trigger to run from) */
  runPanelContext: {
    jobId?: string | null;
    triggerId?: string | null;
  } | null;
}

/**
 * UI store command interface (CQS pattern - Commands)
 */
export interface UICommands {
  /** Open run panel with context */
  openRunPanel: (context: { jobId?: string; triggerId?: string }) => void;

  /** Close run panel */
  closeRunPanel: () => void;
}

/**
 * UI store query interface (CQS pattern - Queries)
 */
export interface UIQueries {
  /** Get current UI state snapshot */
  getSnapshot: () => UIState;

  /** Subscribe to state changes */
  subscribe: (listener: () => void) => () => void;

  /** Create memoized selector for referential stability */
  withSelector: <T>(selector: (state: UIState) => T) => () => T;
}

/**
 * Complete UI store interface combining commands and queries
 */
export type UIStore = UICommands & UIQueries;
