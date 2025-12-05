/**
 * Store Mock Factories
 *
 * Standardized mock factories for collaborative editor stores. These provide
 * complete, well-typed mock implementations with all required methods present
 * by default, eliminating issues with incomplete mocks like `{} as any`.
 *
 * ## Why These Exist
 *
 * When PR #4102 added `getLimits` to SessionContextStore, tests using minimal
 * mocks (`sessionContextStore: {} as any`) broke because the method wasn't present.
 * These factories ensure all required methods exist and can be overridden as needed.
 *
 * ## Usage Pattern
 *
 * ```typescript
 * // Basic usage - all methods present with sensible defaults
 * const sessionContextStore = createMockSessionContextStore();
 *
 * // Override specific methods or state
 * const sessionContextStore = createMockSessionContextStore({
 *   getSnapshot: () => ({
 *     ...defaultSessionContextState,
 *     user: mockUser,
 *   }),
 * });
 *
 * // Full StoreContextValue for StoreProvider tests
 * const stores = createMockStoreContextValue({
 *   sessionContextStore: createMockSessionContextStore({
 *     getSnapshot: () => ({ ...state, user: mockUser }),
 *   }),
 * });
 * ```
 */

import { vi } from 'vitest';

import type { SessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import type { HistoryStore } from '../../../js/collaborative-editor/types/history';
import type { SessionContextState } from '../../../js/collaborative-editor/types/sessionContext';
import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import type { RunDetail } from '../../../js/collaborative-editor/types/history';

// =============================================================================
// Default State Objects
// =============================================================================

/**
 * Default empty session context state
 * Used as the baseline for all mocks
 */
export const defaultSessionContextState: SessionContextState = {
  user: null,
  project: null,
  config: null,
  permissions: null,
  latestSnapshotLockVersion: null,
  projectRepoConnection: null,
  webhookAuthMethods: [],
  versions: [],
  versionsLoading: false,
  versionsError: null,
  workflow_template: null,
  hasReadAIDisclaimer: false,
  limits: {},
  isNewWorkflow: false,
  isLoading: false,
  error: null,
  lastUpdated: null,
};

// =============================================================================
// SessionContextStore Mock Factory
// =============================================================================

/**
 * Creates a mock SessionContextStore with all required methods
 *
 * All methods are vi.fn() mocks that can be inspected and configured.
 * State queries return sensible defaults that can be overridden.
 *
 * @param overrides - Partial SessionContextStore to override defaults
 * @returns Complete SessionContextStore mock
 *
 * @example
 * // Basic usage with default state
 * const store = createMockSessionContextStore();
 * expect(store.getSnapshot().user).toBe(null);
 *
 * @example
 * // Override state
 * const store = createMockSessionContextStore({
 *   getSnapshot: () => ({
 *     ...defaultSessionContextState,
 *     user: mockUser,
 *     permissions: { can_edit_workflow: true, can_run_workflow: true },
 *   }),
 * });
 *
 * @example
 * // Override specific method behavior
 * const store = createMockSessionContextStore({
 *   getLimits: vi.fn().mockRejectedValue(new Error('Network error')),
 * });
 */
export function createMockSessionContextStore(
  overrides: Partial<SessionContextStore> = {}
): SessionContextStore {
  const defaultStore: SessionContextStore = {
    // Queries
    getSnapshot: vi.fn(() => defaultSessionContextState),
    subscribe: vi.fn((listener: () => void) => {
      // Return unsubscribe function
      return () => {};
    }),
    withSelector: vi.fn(<T>(selector: (state: SessionContextState) => T) => {
      return () => selector(defaultSessionContextState);
    }),

    // Commands
    requestSessionContext: vi.fn().mockResolvedValue(undefined),
    requestVersions: vi.fn().mockResolvedValue(undefined),
    clearVersions: vi.fn(),
    setLoading: vi.fn(),
    setError: vi.fn(),
    clearError: vi.fn(),
    setLatestSnapshotLockVersion: vi.fn(),
    clearIsNewWorkflow: vi.fn(),
    setHasReadAIDisclaimer: vi.fn(),
    getLimits: vi.fn().mockResolvedValue(undefined),

    // Internals
    _connectChannel: vi.fn(() => {
      // Return cleanup function
      return () => {};
    }),
  };

  return {
    ...defaultStore,
    ...overrides,
  };
}

// =============================================================================
// HistoryStore Mock Factory
// =============================================================================

/**
 * Creates a mock HistoryStore with all required methods
 *
 * Provides a simplified mock focused on the most commonly used features:
 * - subscribe/withSelector for state observation
 * - activeRun state for run viewer components
 *
 * @param overrides - Partial HistoryStore to override defaults
 * @param activeRun - Optional RunDetail to set as active run
 * @returns Complete HistoryStore mock
 *
 * @example
 * // Basic usage with no active run
 * const store = createMockHistoryStore();
 * expect(store.getActiveRun()).toBe(null);
 *
 * @example
 * // With active run
 * const store = createMockHistoryStore({}, mockRunDetail);
 * expect(store.getActiveRun()).toEqual(mockRunDetail);
 *
 * @example
 * // Override specific methods
 * const store = createMockHistoryStore({
 *   requestHistory: vi.fn().mockRejectedValue(new Error('Failed')),
 * });
 */
export function createMockHistoryStore(
  overrides: Partial<HistoryStore> = {},
  activeRun: RunDetail | null = null
): HistoryStore {
  const defaultState = {
    history: [],
    isLoading: false,
    error: null,
    lastUpdated: null,
    isChannelConnected: false,
    runStepsCache: {},
    runStepsSubscribers: {},
    runStepsLoading: new Set<string>(),
    activeRunId: activeRun?.id ?? null,
    activeRun,
    activeRunChannel: null,
    activeRunLoading: false,
    activeRunError: null,
    selectedStepId: null,
  };

  const defaultStore: HistoryStore = {
    // Queries
    getSnapshot: vi.fn(() => defaultState),
    subscribe: vi.fn((listener: () => void) => {
      return () => {};
    }),
    withSelector: vi.fn(<T>(selector: (state: any) => T) => {
      return () => selector(defaultState);
    }),
    getRunSteps: vi.fn(() => null),
    getActiveRun: vi.fn(() => activeRun),
    getSelectedStep: vi.fn(() => null),
    isActiveRunLoading: vi.fn(() => false),
    getActiveRunError: vi.fn(() => null),

    // Commands
    requestHistory: vi.fn().mockResolvedValue(undefined),
    requestRunSteps: vi.fn().mockResolvedValue(null),
    setLoading: vi.fn(),
    setError: vi.fn(),
    clearError: vi.fn(),
    subscribeToRunSteps: vi.fn(),
    unsubscribeFromRunSteps: vi.fn(),
    _viewRun: vi.fn(),
    _closeRunViewer: vi.fn(),
    selectStep: vi.fn(),
    setActiveRunLoading: vi.fn(),
    setActiveRunError: vi.fn(),
    clearActiveRunError: vi.fn(),

    // Internals
    _connectChannel: vi.fn(() => {
      return () => {};
    }),
    _switchingFromRun: vi.fn(),
    _setActiveRunForTesting: vi.fn(),
  };

  return {
    ...defaultStore,
    ...overrides,
  };
}

// =============================================================================
// Full StoreContextValue Mock Factory
// =============================================================================

/**
 * Creates a complete mock StoreContextValue with all stores
 *
 * Provides a full StoreContextValue suitable for StoreProvider tests.
 * By default, most stores are minimal `{} as any` placeholders except
 * for sessionContextStore and historyStore which use their dedicated
 * mock factories.
 *
 * @param overrides - Partial StoreContextValue to override defaults
 * @returns Complete StoreContextValue mock
 *
 * @example
 * // Basic usage with default stores
 * const stores = createMockStoreContextValue();
 * expect(stores.sessionContextStore).toBeDefined();
 *
 * @example
 * // Override specific stores
 * const stores = createMockStoreContextValue({
 *   sessionContextStore: createMockSessionContextStore({
 *     getSnapshot: () => ({ ...state, user: mockUser }),
 *   }),
 *   historyStore: createMockHistoryStore({}, mockRunDetail),
 * });
 *
 * @example
 * // Use with StoreContext.Provider
 * render(
 *   <StoreContext.Provider value={createMockStoreContextValue()}>
 *     <YourComponent />
 *   </StoreContext.Provider>
 * );
 */
export function createMockStoreContextValue(
  overrides: Partial<StoreContextValue> = {}
): StoreContextValue {
  const defaultStores: StoreContextValue = {
    adaptorStore: {} as any,
    credentialStore: {} as any,
    awarenessStore: {} as any,
    workflowStore: {} as any,
    sessionContextStore: createMockSessionContextStore(),
    historyStore: createMockHistoryStore(),
    uiStore: {} as any,
    editorPreferencesStore: {} as any,
    aiAssistantStore: {} as any,
  };

  return {
    ...defaultStores,
    ...overrides,
  };
}
