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

import type { UICommands, UIState, UIStore } from '../types/ui';

import { createWithSelector } from './common';
import { wrapStoreWithDevTools } from './devtools';

const logger = _logger.ns('UIStore').seal();

/**
 * Creates a UI store instance with useSyncExternalStore + Immer pattern
 */
export const createUIStore = (isNewWorkflow: boolean = false): UIStore => {
  // On /new the landing screen is the only valid entry point — ignore all URL
  // params so ?chat=true can't bypass or corrupt it.
  const loadInitialPanelStates = (): {
    aiAssistantPanelOpen: boolean;
  } => {
    if (isNewWorkflow) {
      return { aiAssistantPanelOpen: false };
    }

    try {
      const params = new URLSearchParams(window.location.search);
      const chatOpen = params.get('chat') === 'true';

      return { aiAssistantPanelOpen: chatOpen };
    } catch (error) {
      logger.warn('Failed to load panel states from URL', error);
      return { aiAssistantPanelOpen: false };
    }
  };

  const { aiAssistantPanelOpen } = loadInitialPanelStates();

  let state: UIState = produce(
    {
      runPanelOpen: false,
      runPanelContext: null,
      githubSyncModalOpen: false,
      aiAssistantPanelOpen,
      aiAssistantInitialMessage: null,
      showLandingScreen: true,
      showYAMLImportModal: false,
      showTemplateBrowserModal: false,
      importPanel: {
        yamlContent: '',
        importState: 'initial',
      },
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

  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  const getSnapshot = (): UIState => state;

  const withSelector = createWithSelector(getSnapshot);

  const openRunPanel: UICommands['openRunPanel'] = context => {
    state = produce(state, draft => {
      draft.runPanelContext = context;
      draft.runPanelOpen = true;
    });
    notify('openRunPanel');
  };

  const closeRunPanel = () => {
    state = produce(state, draft => {
      draft.runPanelContext = null;
      draft.runPanelOpen = false;
    });
    notify('closeRunPanel');
  };

  const openGitHubSyncModal = () => {
    state = produce(state, draft => {
      draft.githubSyncModalOpen = true;
    });
    notify('openGitHubSyncModal');
  };

  const closeGitHubSyncModal = () => {
    state = produce(state, draft => {
      draft.githubSyncModalOpen = false;
    });
    notify('closeGitHubSyncModal');
  };

  const openAIAssistantPanel = (initialMessage?: string) => {
    state = produce(state, draft => {
      draft.aiAssistantPanelOpen = true;
      draft.aiAssistantInitialMessage = initialMessage ?? null;
    });
    notify('openAIAssistantPanel');
  };

  const closeAIAssistantPanel = () => {
    state = produce(state, draft => {
      draft.aiAssistantPanelOpen = false;
      draft.aiAssistantInitialMessage = null;
    });
    notify('closeAIAssistantPanel');
  };

  const toggleAIAssistantPanel = () => {
    const isOpen = !state.aiAssistantPanelOpen;
    state = produce(state, draft => {
      draft.aiAssistantPanelOpen = isOpen;
    });
    notify('toggleAIAssistantPanel');
  };

  const clearAIAssistantInitialMessage = () => {
    state = produce(state, draft => {
      draft.aiAssistantInitialMessage = null;
    });
    notify('clearAIAssistantInitialMessage');
  };

  // ===========================================================================
  // IMPORT PANEL COMMANDS
  // ===========================================================================

  const setImportYamlContent = (content: string) => {
    state = produce(state, draft => {
      draft.importPanel.yamlContent = content;
    });
    notify('setImportYamlContent');
  };

  const setImportState = (
    importState: 'initial' | 'parsing' | 'valid' | 'invalid' | 'importing'
  ) => {
    state = produce(state, draft => {
      draft.importPanel.importState = importState;
    });
    notify('setImportState');
  };

  const clearImportPanel = () => {
    state = produce(state, draft => {
      draft.importPanel = {
        yamlContent: '',
        importState: 'initial',
      };
    });
    notify('clearImportPanel');
  };

  const dismissLandingScreen = () => {
    state = produce(state, draft => {
      draft.showLandingScreen = false;
    });
    notify('dismissLandingScreen');
  };

  const openYAMLImportModal = () => {
    state = produce(state, draft => {
      draft.showYAMLImportModal = true;
    });
    notify('openYAMLImportModal');
  };

  const closeYAMLImportModal = () => {
    state = produce(state, draft => {
      draft.showYAMLImportModal = false;
      draft.importPanel = { yamlContent: '', importState: 'initial' };
    });
    notify('closeYAMLImportModal');
  };

  const openTemplateBrowserModal = () => {
    state = produce(state, draft => {
      draft.showTemplateBrowserModal = true;
    });
    notify('openTemplateBrowserModal');
  };

  const closeTemplateBrowserModal = () => {
    state = produce(state, draft => {
      draft.showTemplateBrowserModal = false;
    });
    notify('closeTemplateBrowserModal');
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
    clearAIAssistantInitialMessage,
    setImportYamlContent,
    setImportState,
    clearImportPanel,
    dismissLandingScreen,
    openYAMLImportModal,
    closeYAMLImportModal,
    openTemplateBrowserModal,
    closeTemplateBrowserModal,
  };
};

export type UIStoreInstance = ReturnType<typeof createUIStore>;
