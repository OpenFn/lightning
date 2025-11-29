/**
 * # UIStore
 *
 * Manages transient UI state like panel visibility and context.
 * Follows the useSyncExternalStore + Immer pattern used across
 * the collaborative editor.
 *
 * ## Core Principles:
 * - Immer for referentially stable state updates
 * - Command Query Separation (CQS) for predictable state mutations
 * - Single source of truth for UI state
 * - Local state only (not synchronized via Y.Doc)
 *
 * ## Update Pattern:
 *
 * ### Pattern 3: Direct Immer → Notify (Local State Only)
 * **When to use**: All UI state updates (panel visibility, context)
 * **Flow**: Direct Immer update → React notification
 * **Benefits**: Immediate response, simple implementation
 *
 * ```typescript
 * // Example: Open run panel with context
 * const openRunPanel = (context: { jobId?: string; triggerId?: string }) => {
 *   state = produce(state, draft => {
 *     draft.activePanel = 'run';
 *     draft.runPanelContext = context;
 *   });
 *   notify('openRunPanel');
 * };
 * ```
 *
 * ## Architecture Notes:
 * - This state is transient and local to each user
 * - No Y.Doc or channel synchronization
 * - Store provides both commands and queries following CQS pattern
 * - withSelector utility provides memoized selectors for performance
 */

/**
 * ## Redux DevTools Integration
 *
 * This store integrates with Redux DevTools for debugging in
 * development and test environments.
 *
 * **Features:**
 * - Real-time state inspection
 * - Action history with timestamps
 * - Time-travel debugging (jump to previous states)
 * - State export/import for reproducing bugs
 *
 * **Usage:**
 * 1. Install Redux DevTools browser extension
 * 2. Open DevTools and select the "UIStore" instance
 * 3. Perform actions in the app and watch them appear in DevTools
 *
 * **Note:** DevTools is automatically disabled in production builds.
 *
 * **Excluded from DevTools:**
 * None (all state is serializable)
 */

import { produce } from 'immer';

import _logger from '#/utils/logger';

import type { UIState, UIStore } from '../types/ui';

import { createWithSelector } from './common';
import { wrapStoreWithDevTools } from './devtools';

const logger = _logger.ns('UIStore').seal();

/**
 * Creates a UI store instance with useSyncExternalStore + Immer pattern
 */
export const createUIStore = (): UIStore => {
  const loadAIAssistantPanelState = (): boolean => {
    try {
      const params = new URLSearchParams(window.location.search);
      return params.get('chat') === 'true';
    } catch (error) {
      logger.warn('Failed to load AI Assistant panel state from URL', error);
      return false;
    }
  };

  let state: UIState = produce(
    {
      runPanelOpen: false,
      runPanelContext: null,
      githubSyncModalOpen: false,
      aiAssistantPanelOpen: loadAIAssistantPanelState(),
    } as UIState,
    draft => draft
  );

  const listeners = new Set<() => void>();

  const devtools = wrapStoreWithDevTools({
    name: 'UIStore',
    excludeKeys: [],
    maxAge: 50,
  });

  const notify = (actionName: string = 'stateChange') => {
    devtools.notifyWithAction(actionName, () => state);
    listeners.forEach(listener => {
      listener();
    });
  };

  // ===========================================================================
  // CORE STORE INTERFACE
  // ===========================================================================

  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  const getSnapshot = (): UIState => state;

  const withSelector = createWithSelector(getSnapshot);

  // ===========================================================================
  // COMMANDS (CQS pattern - State mutations)
  // ===========================================================================

  const openRunPanel = (context: { jobId?: string; triggerId?: string }) => {
    logger.debug('Opening run panel', { context });
    state = produce(state, draft => {
      draft.runPanelContext = context;
      draft.runPanelOpen = true;
    });
    notify('openRunPanel');
  };

  const closeRunPanel = () => {
    logger.debug('Closing run panel');
    state = produce(state, draft => {
      draft.runPanelContext = null;
      draft.runPanelOpen = false;
    });
    notify('closeRunPanel');
  };

  const openGitHubSyncModal = () => {
    logger.debug('Opening GitHub sync modal');
    state = produce(state, draft => {
      draft.githubSyncModalOpen = true;
    });
    notify('openGitHubSyncModal');
  };

  const closeGitHubSyncModal = () => {
    logger.debug('Closing GitHub sync modal');
    state = produce(state, draft => {
      draft.githubSyncModalOpen = false;
    });
    notify('closeGitHubSyncModal');
  };

  const openAIAssistantPanel = () => {
    logger.debug('Opening AI Assistant panel');
    state = produce(state, draft => {
      draft.aiAssistantPanelOpen = true;
    });
    notify('openAIAssistantPanel');
  };

  const closeAIAssistantPanel = () => {
    logger.debug('Closing AI Assistant panel');
    state = produce(state, draft => {
      draft.aiAssistantPanelOpen = false;
    });
    notify('closeAIAssistantPanel');
  };

  const toggleAIAssistantPanel = () => {
    const isOpen = !state.aiAssistantPanelOpen;
    logger.debug(`Toggling AI Assistant panel: ${isOpen ? 'open' : 'closed'}`);
    state = produce(state, draft => {
      draft.aiAssistantPanelOpen = isOpen;
    });
    notify('toggleAIAssistantPanel');
  };

  devtools.connect();

  // ===========================================================================
  // PUBLIC INTERFACE
  // ===========================================================================

  return {
    // Core store interface
    subscribe,
    getSnapshot,
    withSelector,

    // Commands
    openRunPanel,
    closeRunPanel,
    openGitHubSyncModal,
    closeGitHubSyncModal,
    openAIAssistantPanel,
    closeAIAssistantPanel,
    toggleAIAssistantPanel,
  };
};

export type UIStoreInstance = ReturnType<typeof createUIStore>;
