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

// ===========================================================================
// LOCAL STORAGE HELPERS
// ===========================================================================

const FULLSCREEN_STORAGE_KEY = 'lightning.ide.fullscreen';

/**
 * Load IDE fullscreen state from localStorage
 */
const loadIDEFullscreen = (): boolean => {
  try {
    const saved = localStorage.getItem(FULLSCREEN_STORAGE_KEY);
    return saved === 'true';
  } catch (error) {
    logger.warn('Failed to load IDE fullscreen state from localStorage', error);
    return false;
  }
};

/**
 * Save IDE fullscreen state to localStorage
 */
const saveIDEFullscreen = (isFullscreen: boolean): void => {
  try {
    localStorage.setItem(FULLSCREEN_STORAGE_KEY, String(isFullscreen));
  } catch (error) {
    logger.warn('Failed to save IDE fullscreen state to localStorage', error);
  }
};

/**
 * Programmatically collapse the sidebar by triggering the LiveView toggle
 */
const collapseSidebar = (): void => {
  try {
    const sidebarPanel = document.getElementById('sidebar-panel');
    const isCollapsed = sidebarPanel?.dataset.collapsed === 'true';
    if (!isCollapsed) {
      const toggleButton = document.querySelector(
        '[phx-click="toggle_sidebar"]'
      ) as HTMLButtonElement;
      toggleButton?.click();
    }
  } catch (error) {
    logger.warn('Failed to collapse sidebar', error);
  }
};

/**
 * Creates a UI store instance with useSyncExternalStore + Immer pattern
 */
export const createUIStore = (): UIStore => {
  // Load initial panel states from URL params with mutual exclusivity
  // AI Assistant panel and Create Workflow panel cannot both be open
  const loadInitialPanelStates = (): {
    aiAssistantPanelOpen: boolean;
    createWorkflowPanelCollapsed: boolean;
  } => {
    try {
      const params = new URLSearchParams(window.location.search);
      const chatOpen = params.get('chat') === 'true';
      const method = params.get('method');
      const hasMethod = !!method;

      // AI Assistant takes priority when both are present
      if (chatOpen) {
        return {
          aiAssistantPanelOpen: true,
          createWorkflowPanelCollapsed: true, // Force collapsed when AI panel is open
        };
      }

      return {
        aiAssistantPanelOpen: false,
        createWorkflowPanelCollapsed: !hasMethod, // Expanded if method param present
      };
    } catch (error) {
      logger.warn('Failed to load panel states from URL', error);
      return {
        aiAssistantPanelOpen: false,
        createWorkflowPanelCollapsed: true,
      };
    }
  };

  const { aiAssistantPanelOpen, createWorkflowPanelCollapsed } =
    loadInitialPanelStates();

  let state: UIState = produce(
    {
      runPanelOpen: false,
      runPanelContext: null,
      githubSyncModalOpen: false,
      aiAssistantPanelOpen,
      aiAssistantInitialMessage: null,
      createWorkflowPanelCollapsed,
      templatePanel: {
        templates: [],
        loading: false,
        error: null,
        searchQuery: '',
        selectedTemplate: null,
      },
      importPanel: {
        yamlContent: '',
        importState: 'initial',
      },
      ideFullscreen: loadIDEFullscreen(),
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

  const openRunPanel = (context: { jobId?: string; triggerId?: string }) => {
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

  const collapseCreateWorkflowPanel = () => {
    state = produce(state, draft => {
      draft.createWorkflowPanelCollapsed = true;
    });
    notify('collapseCreateWorkflowPanel');
  };

  const expandCreateWorkflowPanel = () => {
    state = produce(state, draft => {
      draft.createWorkflowPanelCollapsed = false;
    });
    notify('expandCreateWorkflowPanel');
  };

  const toggleCreateWorkflowPanel = () => {
    const isCollapsed = !state.createWorkflowPanelCollapsed;
    state = produce(state, draft => {
      draft.createWorkflowPanelCollapsed = isCollapsed;
    });
    notify('toggleCreateWorkflowPanel');
  };

  const setTemplates = (templates: UIState['templatePanel']['templates']) => {
    state = produce(state, draft => {
      draft.templatePanel.templates = templates;
      draft.templatePanel.loading = false;
    });
    notify('setTemplates');
  };

  const setTemplatesLoading = (loading: boolean) => {
    state = produce(state, draft => {
      draft.templatePanel.loading = loading;
    });
    notify('setTemplatesLoading');
  };

  const setTemplatesError = (error: string | null) => {
    state = produce(state, draft => {
      draft.templatePanel.error = error;
      draft.templatePanel.loading = false;
    });
    notify('setTemplatesError');
  };

  const setTemplateSearchQuery = (query: string) => {
    state = produce(state, draft => {
      draft.templatePanel.searchQuery = query;
    });
    notify('setTemplateSearchQuery');
  };

  const selectTemplate = (
    template: UIState['templatePanel']['selectedTemplate']
  ) => {
    state = produce(state, draft => {
      draft.templatePanel.selectedTemplate = template;
    });
    notify('selectTemplate');
  };

  const clearTemplatePanel = () => {
    state = produce(state, draft => {
      draft.templatePanel = {
        templates: [],
        loading: false,
        error: null,
        searchQuery: '',
        selectedTemplate: null,
      };
    });
    notify('clearTemplatePanel');
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

  // ===========================================================================
  // IDE FULLSCREEN COMMANDS
  // ===========================================================================

  const enterIDEFullscreen = () => {
    saveIDEFullscreen(true);
    collapseSidebar();
    state = produce(state, draft => {
      draft.ideFullscreen = true;
    });
    notify('enterIDEFullscreen');
  };

  const exitIDEFullscreen = () => {
    saveIDEFullscreen(false);
    state = produce(state, draft => {
      draft.ideFullscreen = false;
    });
    notify('exitIDEFullscreen');
  };

  const toggleIDEFullscreen = () => {
    if (state.ideFullscreen) {
      exitIDEFullscreen();
    } else {
      enterIDEFullscreen();
    }
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
    collapseCreateWorkflowPanel,
    expandCreateWorkflowPanel,
    toggleCreateWorkflowPanel,
    setTemplates,
    setTemplatesLoading,
    setTemplatesError,
    setTemplateSearchQuery,
    selectTemplate,
    clearTemplatePanel,
    setImportYamlContent,
    setImportState,
    clearImportPanel,
    enterIDEFullscreen,
    exitIDEFullscreen,
    toggleIDEFullscreen,
  };
};

export type UIStoreInstance = ReturnType<typeof createUIStore>;
