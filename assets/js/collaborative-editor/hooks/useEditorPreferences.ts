/**
 * EditorPreferences Hooks
 *
 * React hooks for consuming the EditorPreferencesStore.
 * Follows the established pattern from useHistory.ts and useCredentials.ts.
 */

import { useContext, useSyncExternalStore } from 'react';

import { StoreContext } from '../contexts/StoreProvider';
import type { EditorPreferencesStore } from '../types/editorPreferences';

/**
 * Main hook for accessing the EditorPreferencesStore instance
 * Handles context access and error handling once
 * @private Internal use only
 */
const useEditorPreferencesStore = (): EditorPreferencesStore => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error(
      'useEditorPreferencesStore must be used within a StoreProvider'
    );
  }
  return context.editorPreferencesStore;
};

/**
 * Hook to get history panel collapsed state
 * Returns referentially stable boolean that only changes when
 * preference changes
 *
 * @example
 * const collapsed = useHistoryPanelCollapsed();
 * // collapsed: boolean
 */
export const useHistoryPanelCollapsed = (): boolean => {
  const store = useEditorPreferencesStore();
  const selectCollapsed = store.withSelector(
    state => state.historyPanelCollapsed
  );
  return useSyncExternalStore(store.subscribe, selectCollapsed);
};

/**
 * Hook to get editor preferences commands for triggering actions
 * Returns stable function references that won't cause re-renders
 *
 * @example
 * const { setHistoryPanelCollapsed } = useEditorPreferencesCommands();
 * setHistoryPanelCollapsed(false);
 */
export const useEditorPreferencesCommands = () => {
  const store = useEditorPreferencesStore();

  // These are already stable function references from the store
  return {
    setHistoryPanelCollapsed: store.setHistoryPanelCollapsed,
    resetToDefaults: store.resetToDefaults,
  };
};
