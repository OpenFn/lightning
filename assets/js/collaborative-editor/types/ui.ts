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
  /** Currently active panel (null = no panel open) */
  activePanel: "inspector" | "run" | "ide" | null;

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

  /** Set active panel (generic) */
  setActivePanel: (panel: UIState["activePanel"]) => void;
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

  /** Get currently active panel */
  getActivePanel: () => UIState["activePanel"];

  /** Get run panel context */
  getRunPanelContext: () => UIState["runPanelContext"];
}

/**
 * Complete UI store interface combining commands and queries
 */
export type UIStore = UICommands & UIQueries;
