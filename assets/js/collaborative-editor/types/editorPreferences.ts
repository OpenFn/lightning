/**
 * EditorPreferences Store Types
 *
 * Manages local user preferences for the collaborative editor.
 * Uses lib0/storage for persistence (isomorphic localStorage wrapper).
 */

/**
 * Preference keys supported by the store
 * Add new preferences here as they're needed
 */
export type EditorPreferenceKey = 'historyPanelCollapsed';

/**
 * Type-safe value types for each preference key
 */
export type EditorPreferenceValue<K extends EditorPreferenceKey> =
  K extends 'historyPanelCollapsed' ? boolean : never;

/**
 * Store state shape
 */
export interface EditorPreferencesState {
  historyPanelCollapsed: boolean;
}

/**
 * Commands interface - Following CQS pattern
 * Commands mutate state and return void
 */
interface EditorPreferencesCommands {
  setHistoryPanelCollapsed: (collapsed: boolean) => void;
  resetToDefaults: () => void;
}

/**
 * Queries interface - Following CQS pattern
 * Queries return data without side effects
 */
interface EditorPreferencesQueries {
  getSnapshot: () => EditorPreferencesState;
  subscribe: (listener: () => void) => () => void;
  withSelector: <T>(selector: (state: EditorPreferencesState) => T) => () => T;
}

/**
 * Full EditorPreferencesStore interface
 * Combines queries and commands following CQS pattern
 */
export type EditorPreferencesStore = EditorPreferencesQueries &
  EditorPreferencesCommands;
