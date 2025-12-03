/**
 * React hooks for UI store management
 *
 * Provides convenient hooks for components to access UI state
 * from the StoreProvider context using the useSyncExternalStore pattern.
 */

import { useContext, useSyncExternalStore } from 'react';

import { StoreContext } from '../contexts/StoreProvider';
import type { UIStoreInstance } from '../stores/createUIStore';
import type { UIState } from '../types/ui';

/**
 * Main hook for accessing the UIStore instance
 * Handles context access and error handling once
 */
const useUIStore = (): UIStoreInstance => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error('useUIStore must be used within a StoreProvider');
  }
  return context.uiStore;
};

/**
 * Hook to get run panel context
 * Returns null when run panel is not open
 */
export const useRunPanelContext = (): UIState['runPanelContext'] => {
  const uiStore = useUIStore();

  const selectRunPanelContext = uiStore.withSelector(
    state => state.runPanelContext
  );

  return useSyncExternalStore(uiStore.subscribe, selectRunPanelContext);
};

/**
 * Hook to get UI commands for triggering actions
 * Returns stable function references
 */
export const useUICommands = () => {
  const uiStore = useUIStore();

  // These are already stable function references from the store
  return {
    openRunPanel: uiStore.openRunPanel,
    closeRunPanel: uiStore.closeRunPanel,
    openGitHubSyncModal: uiStore.openGitHubSyncModal,
    closeGitHubSyncModal: uiStore.closeGitHubSyncModal,
    openAIAssistantPanel: uiStore.openAIAssistantPanel,
    closeAIAssistantPanel: uiStore.closeAIAssistantPanel,
    toggleAIAssistantPanel: uiStore.toggleAIAssistantPanel,
    clearAIAssistantInitialMessage: uiStore.clearAIAssistantInitialMessage,
    collapseCreateWorkflowPanel: uiStore.collapseCreateWorkflowPanel,
    expandCreateWorkflowPanel: uiStore.expandCreateWorkflowPanel,
    toggleCreateWorkflowPanel: uiStore.toggleCreateWorkflowPanel,
    // Template panel commands
    selectTemplate: uiStore.selectTemplate,
    setTemplateSearchQuery: uiStore.setTemplateSearchQuery,
  };
};

/**
 * Hook to check if run panel is open
 * Convenience helper that returns boolean
 */
export const useIsRunPanelOpen = (): boolean => {
  const uiStore = useUIStore();

  const selectIsOpen = uiStore.withSelector(state => state.runPanelOpen);

  return useSyncExternalStore(uiStore.subscribe, selectIsOpen);
};

/**
 * Hook to check if GitHub sync modal is open
 * Convenience helper that returns boolean
 */
export const useIsGitHubSyncModalOpen = (): boolean => {
  const uiStore = useUIStore();

  const selectIsOpen = uiStore.withSelector(state => state.githubSyncModalOpen);

  return useSyncExternalStore(uiStore.subscribe, selectIsOpen);
};

/**
 * Hook to check if AI Assistant panel is open
 * Convenience helper that returns boolean
 */
export const useIsAIAssistantPanelOpen = (): boolean => {
  const uiStore = useUIStore();

  const selectIsOpen = uiStore.withSelector(
    state => state.aiAssistantPanelOpen
  );

  return useSyncExternalStore(uiStore.subscribe, selectIsOpen);
};

/**
 * Hook to get AI Assistant initial message
 * Returns the message to send when panel opens, or null
 */
export const useAIAssistantInitialMessage = (): string | null => {
  const uiStore = useUIStore();

  const selectInitialMessage = uiStore.withSelector(
    state => state.aiAssistantInitialMessage
  );

  return useSyncExternalStore(uiStore.subscribe, selectInitialMessage);
};

/**
 * Hook to check if create workflow panel is collapsed
 * Convenience helper that returns boolean
 */
export const useIsCreateWorkflowPanelCollapsed = (): boolean => {
  const uiStore = useUIStore();

  const selectIsCollapsed = uiStore.withSelector(
    state => state.createWorkflowPanelCollapsed
  );

  return useSyncExternalStore(uiStore.subscribe, selectIsCollapsed);
};

/**
 * Hook to get the entire template panel state
 * Returns properly typed state - no type assertions needed
 */
export const useTemplatePanel = (): UIState['templatePanel'] => {
  const uiStore = useUIStore();

  const selectTemplatePanel = uiStore.withSelector(
    state => state.templatePanel
  );

  return useSyncExternalStore(uiStore.subscribe, selectTemplatePanel);
};

/**
 * Hook to get the import panel state
 */
export const useImportPanelState =
  (): UIState['importPanel']['importState'] => {
    const uiStore = useUIStore();

    const selectImportState = uiStore.withSelector(
      state => state.importPanel.importState
    );

    return useSyncExternalStore(uiStore.subscribe, selectImportState);
  };
