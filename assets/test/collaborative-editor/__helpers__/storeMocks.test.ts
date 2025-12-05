/**
 * Tests for Store Mock Factories
 *
 * Verifies that mock factories provide complete, well-typed implementations
 * with all required methods present.
 */

import { describe, it, expect, vi } from 'vitest';

import {
  createMockSessionContextStore,
  createMockHistoryStore,
  createMockStoreContextValue,
  defaultSessionContextState,
} from './storeMocks';
import { mockUserContext } from './sessionContextFactory';

describe('storeMocks', () => {
  describe('createMockSessionContextStore', () => {
    it('creates a store with all required methods', () => {
      const store = createMockSessionContextStore();

      // Verify queries exist
      expect(store.getSnapshot).toBeInstanceOf(Function);
      expect(store.subscribe).toBeInstanceOf(Function);
      expect(store.withSelector).toBeInstanceOf(Function);

      // Verify commands exist
      expect(store.requestSessionContext).toBeInstanceOf(Function);
      expect(store.requestVersions).toBeInstanceOf(Function);
      expect(store.clearVersions).toBeInstanceOf(Function);
      expect(store.setLoading).toBeInstanceOf(Function);
      expect(store.setError).toBeInstanceOf(Function);
      expect(store.clearError).toBeInstanceOf(Function);
      expect(store.setLatestSnapshotLockVersion).toBeInstanceOf(Function);
      expect(store.clearIsNewWorkflow).toBeInstanceOf(Function);
      expect(store.getLimits).toBeInstanceOf(Function);

      // Verify internals exist
      expect(store._connectChannel).toBeInstanceOf(Function);
    });

    it('returns default empty state', () => {
      const store = createMockSessionContextStore();
      const state = store.getSnapshot();

      expect(state).toEqual(defaultSessionContextState);
      expect(state.user).toBe(null);
      expect(state.project).toBe(null);
      expect(state.isLoading).toBe(false);
    });

    it('allows overriding getSnapshot', () => {
      const customState = {
        ...defaultSessionContextState,
        user: mockUserContext,
      };

      const store = createMockSessionContextStore({
        getSnapshot: vi.fn(() => customState),
      });

      const state = store.getSnapshot();
      expect(state.user).toEqual(mockUserContext);
    });

    it('allows overriding specific methods', () => {
      const mockGetLimits = vi
        .fn()
        .mockRejectedValue(new Error('Network error'));

      const store = createMockSessionContextStore({
        getLimits: mockGetLimits,
      });

      expect(store.getLimits).toBe(mockGetLimits);
    });

    it('subscribe returns unsubscribe function', () => {
      const store = createMockSessionContextStore();
      const unsubscribe = store.subscribe(() => {});

      expect(unsubscribe).toBeInstanceOf(Function);
    });

    it('withSelector returns selector function', () => {
      const store = createMockSessionContextStore();
      const selector = store.withSelector(state => state.user);

      expect(selector).toBeInstanceOf(Function);
      expect(selector()).toBe(null);
    });
  });

  describe('createMockHistoryStore', () => {
    it('creates a store with all required methods', () => {
      const store = createMockHistoryStore();

      // Verify queries exist
      expect(store.getSnapshot).toBeInstanceOf(Function);
      expect(store.subscribe).toBeInstanceOf(Function);
      expect(store.withSelector).toBeInstanceOf(Function);
      expect(store.getRunSteps).toBeInstanceOf(Function);
      expect(store.getActiveRun).toBeInstanceOf(Function);
      expect(store.getSelectedStep).toBeInstanceOf(Function);
      expect(store.isActiveRunLoading).toBeInstanceOf(Function);
      expect(store.getActiveRunError).toBeInstanceOf(Function);

      // Verify commands exist
      expect(store.requestHistory).toBeInstanceOf(Function);
      expect(store.requestRunSteps).toBeInstanceOf(Function);
      expect(store.setLoading).toBeInstanceOf(Function);
      expect(store.setError).toBeInstanceOf(Function);
      expect(store.clearError).toBeInstanceOf(Function);
      expect(store.subscribeToRunSteps).toBeInstanceOf(Function);
      expect(store.unsubscribeFromRunSteps).toBeInstanceOf(Function);
      expect(store.selectStep).toBeInstanceOf(Function);

      // Verify internals exist
      expect(store._connectChannel).toBeInstanceOf(Function);
      expect(store._viewRun).toBeInstanceOf(Function);
      expect(store._closeRunViewer).toBeInstanceOf(Function);
    });

    it('returns default state with no active run', () => {
      const store = createMockHistoryStore();

      expect(store.getActiveRun()).toBe(null);
      expect(store.getSelectedStep()).toBe(null);
      expect(store.isActiveRunLoading()).toBe(false);
      expect(store.getActiveRunError()).toBe(null);
    });

    it('accepts activeRun parameter', () => {
      const mockRun = {
        id: 'run-123',
        work_order_id: 'wo-123',
        work_order: {
          id: 'wo-123',
          workflow_id: 'wf-123',
        },
        state: 'success' as const,
        created_by: null,
        starting_trigger: null,
        started_at: '2024-01-01T00:00:00Z',
        finished_at: '2024-01-01T00:01:00Z',
        inserted_at: '2024-01-01T00:00:00Z',
        steps: [],
      };

      const store = createMockHistoryStore({}, mockRun);

      expect(store.getActiveRun()).toEqual(mockRun);
    });

    it('allows overriding specific methods', () => {
      const mockRequestHistory = vi.fn().mockRejectedValue(new Error('Failed'));

      const store = createMockHistoryStore({
        requestHistory: mockRequestHistory,
      });

      expect(store.requestHistory).toBe(mockRequestHistory);
    });
  });

  describe('createMockStoreContextValue', () => {
    it('creates a complete StoreContextValue', () => {
      const stores = createMockStoreContextValue();

      // Verify all stores are present
      expect(stores.adaptorStore).toBeDefined();
      expect(stores.credentialStore).toBeDefined();
      expect(stores.awarenessStore).toBeDefined();
      expect(stores.workflowStore).toBeDefined();
      expect(stores.sessionContextStore).toBeDefined();
      expect(stores.historyStore).toBeDefined();
      expect(stores.uiStore).toBeDefined();
      expect(stores.editorPreferencesStore).toBeDefined();
    });

    it('uses createMockSessionContextStore by default', () => {
      const stores = createMockStoreContextValue();

      expect(stores.sessionContextStore.getSnapshot).toBeInstanceOf(Function);
      expect(stores.sessionContextStore.getLimits).toBeInstanceOf(Function);
    });

    it('uses createMockHistoryStore by default', () => {
      const stores = createMockStoreContextValue();

      expect(stores.historyStore.getActiveRun).toBeInstanceOf(Function);
      expect(stores.historyStore.requestHistory).toBeInstanceOf(Function);
    });

    it('allows overriding specific stores', () => {
      const customSessionStore = createMockSessionContextStore({
        getSnapshot: vi.fn(() => ({
          ...defaultSessionContextState,
          user: mockUserContext,
        })),
      });

      const stores = createMockStoreContextValue({
        sessionContextStore: customSessionStore,
      });

      expect(stores.sessionContextStore).toBe(customSessionStore);
      expect(stores.sessionContextStore.getSnapshot().user).toEqual(
        mockUserContext
      );
    });
  });

  describe('defaultSessionContextState', () => {
    it('provides sensible defaults', () => {
      expect(defaultSessionContextState.user).toBe(null);
      expect(defaultSessionContextState.project).toBe(null);
      expect(defaultSessionContextState.config).toBe(null);
      expect(defaultSessionContextState.permissions).toBe(null);
      expect(defaultSessionContextState.isLoading).toBe(false);
      expect(defaultSessionContextState.error).toBe(null);
      expect(defaultSessionContextState.isNewWorkflow).toBe(false);
      expect(defaultSessionContextState.webhookAuthMethods).toEqual([]);
      expect(defaultSessionContextState.versions).toEqual([]);
    });
  });
});
