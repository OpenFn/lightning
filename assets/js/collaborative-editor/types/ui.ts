/**
 * UI type definitions
 *
 * Defines the shape of transient UI state like panel visibility
 * and context for the collaborative editor.
 */

import type { Template, WorkflowTemplate } from './template';

// =============================================================================
// TYPESCRIPT TYPES
// =============================================================================

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
  } | null;

  /** GitHub sync modal open state */
  githubSyncModalOpen: boolean;

  /** AI Assistant panel open state */
  aiAssistantPanelOpen: boolean;

  /** Initial message to send when AI Assistant panel opens */
  aiAssistantInitialMessage: string | null;

  /** Template panel state */
  templatePanel: {
    templates: WorkflowTemplate[];
    loading: boolean;
    error: string | null;
    searchQuery: string;
    selectedTemplate: Template | null;
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

  /** Set templates list */
  setTemplates: (templates: WorkflowTemplate[]) => void;

  /** Set templates loading state */
  setTemplatesLoading: (loading: boolean) => void;

  /** Set templates error */
  setTemplatesError: (error: string | null) => void;

  /** Set template search query */
  setTemplateSearchQuery: (query: string) => void;

  /** Select a template */
  selectTemplate: (template: Template | null) => void;

  /** Clear template panel state */
  clearTemplatePanel: () => void;
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
