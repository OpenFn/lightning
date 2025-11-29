/**
 * AI Assistant Hooks
 *
 * React hooks for accessing AI Assistant store state and commands.
 * Follows the same pattern as other store hooks (useUI, useWorkflow, etc.)
 */

import { useSyncExternalStore, useContext } from 'react';

import { StoreContext } from '../contexts/StoreProvider';
import type { AIAssistantStoreInstance } from '../stores/createAIAssistantStore';

/**
 * Get AI Assistant store instance
 */
export const useAIStore = (): AIAssistantStoreInstance => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error('useAIStore must be used within a StoreProvider');
  }
  return context.aiAssistantStore;
};

/**
 * Get all AI Assistant commands
 */
export const useAICommands = () => {
  const store = useAIStore();
  return {
    connect: store.connect,
    disconnect: store.disconnect,
    sendMessage: store.sendMessage,
    retryMessage: store.retryMessage,
    markDisclaimerRead: store.markDisclaimerRead,
    clearSession: store.clearSession,
  };
};

/**
 * Get AI connection state
 */
export const useAIConnectionState = () => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.connectionState)
  );
};

/**
 * Get AI connection error
 */
export const useAIConnectionError = () => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.connectionError)
  );
};

/**
 * Get current session ID
 */
export const useAISessionId = () => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.sessionId)
  );
};

/**
 * Get current session type
 */
export const useAISessionType = () => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.sessionType)
  );
};

/**
 * Get all chat messages
 */
export const useAIMessages = () => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.messages)
  );
};

/**
 * Get loading state
 */
export const useAIIsLoading = () => {
  const store = useAIStore();
  const isLoading = useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.isLoading)
  );

  return isLoading;
};

/**
 * Get sending state
 */
export const useAIIsSending = () => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.isSending)
  );
};

/**
 * Get disclaimer read state
 */
export const useAIHasReadDisclaimer = () => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.hasReadDisclaimer)
  );
};

/**
 * Get job code context
 */
export const useAIJobCodeContext = () => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.jobCodeContext)
  );
};

/**
 * Get workflow template context
 */
export const useAIWorkflowTemplateContext = () => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.workflowTemplateContext)
  );
};
