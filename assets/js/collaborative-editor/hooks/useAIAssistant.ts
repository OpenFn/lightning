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
    setMessageSending: store.setMessageSending,
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
    store.withSelector(state => state.workflowTemplateContext?.job_ctx)
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

/**
 * Get session list
 */
export const useAISessionList = () => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.sessionList)
  );
};

/**
 * Get session list loading state
 */
export const useAISessionListLoading = () => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.sessionListLoading)
  );
};

/**
 * Get session list pagination
 */
export const useAISessionListPagination = () => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.sessionListPagination)
  );
};

/**
 * Get computed storage key for persisting chat input drafts.
 * Returns a unique key based on session type and context (job_id, workflow_id, or project_id).
 */
export const useAIStorageKey = (): string | undefined => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => {
      if (state.sessionType === 'job_code' && state.jobCodeContext?.job_id) {
        return `ai-job-${state.jobCodeContext.job_id}`;
      }
      if (state.sessionType === 'workflow_template') {
        if (state.workflowTemplateContext?.workflow_id) {
          return `ai-workflow-${state.workflowTemplateContext.workflow_id}`;
        }
        if (state.workflowTemplateContext?.project_id) {
          return `ai-project-${state.workflowTemplateContext.project_id}`;
        }
      }
      return undefined;
    })
  );
};

/**
 * Check if session context (job or workflow) is set
 */
export const useAIHasSessionContext = () => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(
      state => !!(state.jobCodeContext || state.workflowTemplateContext)
    )
  );
};

/**
 * Check if initial session list load has completed
 */
export const useAIHasCompletedSessionLoad = () => {
  const store = useAIStore();
  return useSyncExternalStore(
    store.subscribe,
    store.withSelector(state => state.sessionListPagination !== null)
  );
};

/**
 * Get session list commands
 */
export const useAISessionListCommands = () => {
  const store = useAIStore();
  return {
    loadSessionList: store.loadSessionList,
  };
};
