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
 * Entry point that opened the run panel. Drives the panel title.
 * - 'custom-input': opened from the canvas Run dropdown or a default
 *   (no specific node) entry path.
 */
export type RunPanelEntryPoint = 'custom-input';

/**
 * UI store state for transient UI concerns like panel visibility
 */
export interface UIState {
  runPanelOpen: boolean;

  /** Context for run panel (which job/trigger/edge is selected) */
  runPanelContext: {
    jobId?: string | null;
    triggerId?: string | null;
    edgeId?: string | null;
    entryPoint?: RunPanelEntryPoint | null;
  } | null;

  /** GitHub sync modal open state */
  githubSyncModalOpen: boolean;

  /** AI Assistant panel open state */
  aiAssistantPanelOpen: boolean;

  /** Initial message to send when AI Assistant panel opens */
  aiAssistantInitialMessage: string | null;

  /** Whether the landing screen overlay is visible (only true at /new before a path is committed) */
  showLandingScreen: boolean;

  /** Whether the YAML import modal is open */
  showYAMLImportModal: boolean;

  /** Whether the template browser modal is open */
  showTemplateBrowserModal: boolean;

  /** Import panel state */
  importPanel: {
    yamlContent: string;
    /** Import state machine: initial -> parsing -> valid/invalid -> importing */
    importState: 'initial' | 'parsing' | 'valid' | 'invalid' | 'importing';
  };
}

/**
 * UI store command interface (CQS pattern - Commands)
 */
export interface UICommands {
  /** Open run panel with context */
  openRunPanel: (context: {
    jobId?: string;
    triggerId?: string;
    edgeId?: string;
    entryPoint?: RunPanelEntryPoint;
  }) => void;

  /** Close run panel */
  closeRunPanel: () => void;

  /** Open GitHub sync modal */
  openGitHubSyncModal: () => void;

  /** Close GitHub sync modal */
  closeGitHubSyncModal: () => void;

  /** Open AI Assistant panel with optional initial message */
  openAIAssistantPanel: (initialMessage?: string) => void;

  /** Close AI Assistant panel */
  closeAIAssistantPanel: () => void;

  /** Toggle AI Assistant panel */
  toggleAIAssistantPanel: () => void;

  /** Dismiss the landing screen — called by downstream issues when a path is committed */
  dismissLandingScreen: () => void;

  /** Open the YAML import modal */
  openYAMLImportModal: () => void;

  /** Close the YAML import modal and reset import panel content */
  closeYAMLImportModal: () => void;

  /** Open the template browser modal */
  openTemplateBrowserModal: () => void;

  /** Close the template browser modal */
  closeTemplateBrowserModal: () => void;

  /** Set import panel YAML content */
  setImportYamlContent: (content: string) => void;

  /** Set import panel state */
  setImportState: (
    state: 'initial' | 'parsing' | 'valid' | 'invalid' | 'importing'
  ) => void;

  /** Clear import panel state */
  clearImportPanel: () => void;
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
