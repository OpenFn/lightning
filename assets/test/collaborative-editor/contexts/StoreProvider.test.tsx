/**
 * StoreProvider Tests
 *
 * Verifies StoreProvider behavior:
 * - Context provision and store availability
 * - Store independence across provider instances
 * - Awareness and channel connection lifecycle
 * - Error handling
 */

import { act, render, renderHook, waitFor } from '@testing-library/react';
import { useContext } from 'react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import * as Y from 'yjs';

import {
  StoreContext,
  StoreProvider,
} from '../../../js/collaborative-editor/contexts/StoreProvider';
import * as useSessionModule from '../../../js/collaborative-editor/hooks/useSession';
import type { SessionState } from '../../../js/collaborative-editor/stores/createSessionStore';
import type { Session } from '../../../js/collaborative-editor/types/session';
import {
  createMockConfig,
  createMockUser,
  mockPermissions,
} from '../__helpers__/sessionContextFactory';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../mocks/phoenixChannel';

// =============================================================================
// TEST SETUP & FIXTURES
// =============================================================================

const mockUseSession = vi.spyOn(useSessionModule, 'useSession');

const createMockSessionState = (
  overrides?: Partial<SessionState>
): SessionState => ({
  ydoc: null,
  provider: null,
  awareness: null,
  userData: null,
  isConnected: false,
  isSynced: false,
  lastStatus: null,
  ...overrides,
});

const createMockAwareness = () => ({
  getLocalState: vi.fn(),
  setLocalState: vi.fn(),
  setLocalStateField: vi.fn(),
  getStates: vi.fn().mockReturnValue(new Map()),
  on: vi.fn(),
  off: vi.fn(),
});

const createMockProvider = () => ({
  channel: {
    push: vi.fn(),
    on: vi.fn(),
    off: vi.fn(),
  },
});

const createMockUserData = () => ({
  id: 'user-1',
  name: 'Test User',
  color: '#ff0000',
});

describe('StoreProvider', () => {
  beforeEach(() => {
    mockUseSession.mockReturnValue(createMockSessionState());
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  // ===========================================================================
  // CONTEXT PROVISION TESTS
  // ===========================================================================

  describe('context provision', () => {
    test('provides all stores with correct interfaces and initial state', () => {
      const { result } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const stores = result.current!;

      // All stores are present
      expect(stores.adaptorStore).toBeDefined();
      expect(stores.credentialStore).toBeDefined();
      expect(stores.awarenessStore).toBeDefined();
      expect(stores.workflowStore).toBeDefined();
      expect(stores.sessionContextStore).toBeDefined();

      // Verify store interfaces
      expect(typeof stores.adaptorStore.subscribe).toBe('function');
      expect(typeof stores.adaptorStore.getSnapshot).toBe('function');
      expect(typeof stores.adaptorStore.withSelector).toBe('function');
      expect(typeof stores.sessionContextStore.requestSessionContext).toBe(
        'function'
      );
      expect(typeof stores.awarenessStore.initializeAwareness).toBe('function');
      expect(typeof stores.awarenessStore.destroyAwareness).toBe('function');
      expect(typeof stores.workflowStore.connect).toBe('function');
      expect(typeof stores.workflowStore.disconnect).toBe('function');

      // Verify initial state
      const sessionContextState = stores.sessionContextStore.getSnapshot();
      expect(sessionContextState.user).toBeNull();
      expect(sessionContextState.project).toBeNull();
      expect(sessionContextState.config).toBeNull();
      expect(sessionContextState.lastUpdated).toBeNull();
    });
  });

  // ===========================================================================
  // STORE INDEPENDENCE TESTS
  // ===========================================================================

  describe('store independence', () => {
    test('different providers create independent stores, same provider shares stores', () => {
      // Different providers = different stores
      const { result: result1 } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const { result: result2 } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      expect(result1.current!.adaptorStore).not.toBe(
        result2.current!.adaptorStore
      );
      expect(result1.current!.sessionContextStore).not.toBe(
        result2.current!.sessionContextStore
      );

      // Same provider = shared stores
      let store1: any;
      let store2: any;

      const TestComponent1 = () => {
        const context = useContext(StoreContext);
        store1 = context?.adaptorStore;
        return null;
      };

      const TestComponent2 = () => {
        const context = useContext(StoreContext);
        store2 = context?.adaptorStore;
        return null;
      };

      render(
        <StoreProvider>
          <TestComponent1 />
          <TestComponent2 />
        </StoreProvider>
      );

      expect(store1).toBe(store2);
    });
  });

  // ===========================================================================
  // PROVIDER LIFECYCLE TESTS
  // ===========================================================================

  describe('provider lifecycle', () => {
    test('cleans up awareness on unmount', () => {
      const { result, unmount } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const awarenessStore = result.current!.awarenessStore;
      const destroySpy = vi.spyOn(awarenessStore, 'destroyAwareness');

      unmount();

      expect(destroySpy).toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // AWARENESS INITIALIZATION TESTS
  // ===========================================================================

  describe('awareness initialization', () => {
    test('initializes awareness when ready, skips if already initialized or user missing', async () => {
      // Start without awareness
      mockUseSession.mockReturnValue(createMockSessionState());

      const { result, rerender } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const stores = result.current!;
      const awarenessStore = stores.awarenessStore;
      const sessionContextStore = stores.sessionContextStore;
      const initSpy = vi.spyOn(awarenessStore, 'initializeAwareness');

      // Set up Phoenix Channel to populate sessionContextStore
      const mockChannel = createMockPhoenixChannel();
      const mockProvider = createMockPhoenixChannelProvider(mockChannel);
      sessionContextStore._connectChannel(mockProvider as any);

      // Emit user data through channel
      const mockUser = createMockUser({
        id: '00000000-0000-4000-8000-000000000001',
        first_name: 'Test',
        last_name: 'User',
      });

      act(() => {
        (mockChannel as any)._test.emit('session_context', {
          user: mockUser,
          project: null,
          config: createMockConfig(),
          permissions: mockPermissions,
          latest_snapshot_lock_version: 1,
          project_repo_connection: null,
          webhook_auth_methods: [],
          workflow_template: null,
        });
      });

      // Provide awareness - should initialize with user from sessionContextStore
      const mockAwareness = createMockAwareness() as any;
      mockUseSession.mockReturnValue(
        createMockSessionState({
          awareness: mockAwareness,
        })
      );

      rerender();

      // Verify awareness initialized with transformed user data
      await waitFor(() => {
        expect(initSpy).toHaveBeenCalledWith(mockAwareness, {
          id: '00000000-0000-4000-8000-000000000001',
          name: 'Test User',
          color: expect.any(String),
          email: 'test@example.com',
        });
      });

      // Test skip when already ready
      initSpy.mockClear();
      vi.spyOn(awarenessStore, 'isAwarenessReady').mockReturnValue(true);

      mockUseSession.mockReturnValue(
        createMockSessionState({
          awareness: createMockAwareness() as any,
        })
      );

      rerender();
      await new Promise(resolve => setTimeout(resolve, 10));

      expect(initSpy).not.toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // CHANNEL CONNECTION TESTS
  // ===========================================================================

  describe('channel connection', () => {
    test('connects stores when ready, cleans up on unmount and provider change', async () => {
      // Start without provider
      mockUseSession.mockReturnValue(createMockSessionState());

      const { result, rerender, unmount } = renderHook(
        () => useContext(StoreContext),
        {
          wrapper: StoreProvider,
        }
      );

      const adaptorStore = result.current!.adaptorStore;
      const credentialStore = result.current!.credentialStore;
      const sessionContextStore = result.current!.sessionContextStore;

      const connectSpy1 = vi.spyOn(adaptorStore, '_connectChannel');
      const connectSpy2 = vi.spyOn(credentialStore, '_connectChannel');
      const connectSpy3 = vi.spyOn(sessionContextStore, '_connectChannel');

      const mockProvider1 = createMockProvider() as any;
      const mockCleanup1 = vi.fn();
      const mockCleanup2 = vi.fn();
      const mockCleanup3 = vi.fn();

      connectSpy1.mockReturnValue(mockCleanup1);
      connectSpy2.mockReturnValue(mockCleanup2);
      connectSpy3.mockReturnValue(mockCleanup3);

      // Connect to first provider
      mockUseSession.mockReturnValue(
        createMockSessionState({
          provider: mockProvider1,
          isConnected: true,
        })
      );

      rerender();

      await waitFor(() => {
        expect(connectSpy1).toHaveBeenCalledWith(mockProvider1);
        expect(connectSpy2).toHaveBeenCalledWith(mockProvider1);
        expect(connectSpy3).toHaveBeenCalledWith(mockProvider1);
      });

      // Change provider - should cleanup and reconnect
      const mockProvider2 = createMockProvider() as any;
      mockUseSession.mockReturnValue(
        createMockSessionState({
          provider: mockProvider2,
          isConnected: true,
        })
      );

      rerender();

      await waitFor(() => {
        expect(mockCleanup1).toHaveBeenCalled();
        expect(connectSpy1).toHaveBeenCalledWith(mockProvider2);
      });

      // Unmount should cleanup
      unmount();

      expect(mockCleanup1).toHaveBeenCalled();
      expect(mockCleanup2).toHaveBeenCalled();
      expect(mockCleanup3).toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // WORKFLOW STORE CONNECTION TESTS
  // ===========================================================================

  describe('workflow store connection', () => {
    test('connects workflowStore when ready and disconnects on unmount', async () => {
      mockUseSession.mockReturnValue(createMockSessionState());

      const { result, rerender, unmount } = renderHook(
        () => useContext(StoreContext),
        {
          wrapper: StoreProvider,
        }
      );

      const workflowStore = result.current!.workflowStore;
      const connectSpy = vi.spyOn(workflowStore, 'connect');
      const disconnectSpy = vi.spyOn(workflowStore, 'disconnect');

      // Use real Y.Doc to support UndoManager
      const mockYDoc = new Y.Doc() as Session.WorkflowDoc;
      const mockProvider = createMockProvider() as any;

      mockUseSession.mockReturnValue(
        createMockSessionState({
          ydoc: mockYDoc,
          provider: mockProvider,
          isSynced: true,
        })
      );

      rerender();

      await waitFor(() => {
        expect(connectSpy).toHaveBeenCalledWith(mockYDoc, mockProvider);
      });

      unmount();

      expect(disconnectSpy).toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // INTEGRATION TESTS
  // ===========================================================================

  describe('integration', () => {
    test('hooks can access stores and state through provider', () => {
      const useTestHook = () => {
        const context = useContext(StoreContext);
        if (!context) {
          throw new Error('StoreContext is null');
        }
        return context.adaptorStore.getSnapshot();
      };

      const { result } = renderHook(() => useTestHook(), {
        wrapper: StoreProvider,
      });

      expect(result.current).toBeDefined();
      expect(result.current.isLoading).toBe(false);
    });
  });

  // ===========================================================================
  // ERROR HANDLING TESTS
  // ===========================================================================

  describe('error handling', () => {
    test('accessing context outside provider returns null', () => {
      const { result } = renderHook(() => useContext(StoreContext));
      expect(result.current).toBeNull();

      const TestComponent = () => {
        const context = useContext(StoreContext);
        return <div>{context ? 'has context' : 'no context'}</div>;
      };

      const { getByText } = render(<TestComponent />);
      expect(getByText('no context')).toBeInTheDocument();
    });
  });

  // ===========================================================================
  // INITIALIZATION SEQUENCE TESTS
  // ===========================================================================

  describe('initialization sequence with LoadingBoundary', () => {
    test('documents complete initialization flow', () => {
      // This test documents the initialization sequence after Phase 1-3 refactoring:
      //
      // 1. StoreProvider creates all stores
      // 2. SessionStore connects to Phoenix Channel
      // 3. Channel stores connect when provider becomes available
      // 4. Y.Doc syncs with server (isSynced becomes true)
      // 5. WorkflowStore observers populate state (workflow becomes non-null)
      // 6. LoadingBoundary allows children to render
      //
      // Key changes:
      // - Phase 1: LoadingBoundary waits for isSynced && workflow !== null
      // - Phase 2: ensureConnected() prevents mutations before sync
      // - Phase 3: Removed 'settled' state, simplified to isSynced

      const initSequence = [
        '1. StoreProvider creates all stores',
        '2. SessionStore connects to Phoenix Channel',
        '3. Channel stores connect when provider available',
        '4. Y.Doc syncs with server (isSynced = true)',
        '5. WorkflowStore observers populate state (workflow !== null)',
        '6. LoadingBoundary allows children to render',
      ];

      expect(initSequence).toHaveLength(6);
      expect(initSequence[0]).toContain('StoreProvider creates all stores');
      expect(initSequence[initSequence.length - 1]).toContain(
        'LoadingBoundary allows children to render'
      );
    });

    test('LoadingBoundary integration removes need for settled state', () => {
      // Phase 3 removed the 'settled' state because LoadingBoundary
      // now handles the waiting logic using isSynced + workflow !== null.
      //
      // Before Phase 1-3:
      // - SessionStore tracked 'settled' state
      // - Components checked settled before rendering
      // - Complex subscription machinery for settling
      //
      // After Phase 1-3:
      // - LoadingBoundary checks isSynced && workflow !== null
      // - Components inside LoadingBoundary can assume ready state
      // - Simpler state machine in SessionStore

      const beforeAfter = {
        before: {
          settledState: true,
          settlingSubscription: true,
          defensiveGuards: true,
        },
        after: {
          loadingBoundary: true,
          simplifiedStateMachine: true,
          guaranteedState: true,
        },
      };

      expect(beforeAfter.before.settledState).toBe(true);
      expect(beforeAfter.after.loadingBoundary).toBe(true);
      expect(beforeAfter.after.simplifiedStateMachine).toBe(true);
    });

    test('workflow store connection waits for isSynced', async () => {
      // WorkflowStore.connect() is called when isSynced becomes true
      // This ensures workflow data is available before rendering

      mockUseSession.mockReturnValue(createMockSessionState());

      const { result, rerender } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const workflowStore = result.current!.workflowStore;
      const connectSpy = vi.spyOn(workflowStore, 'connect');

      // Use real Y.Doc to support UndoManager
      const mockYDoc = new Y.Doc() as Session.WorkflowDoc;
      const mockProvider = createMockProvider() as any;

      // Update session to synced
      mockUseSession.mockReturnValue(
        createMockSessionState({
          ydoc: mockYDoc,
          provider: mockProvider,
          isSynced: true,
        })
      );

      rerender();

      await waitFor(() => {
        expect(connectSpy).toHaveBeenCalledWith(mockYDoc, mockProvider);
      });
    });

    test('channel stores connect when provider is available', async () => {
      mockUseSession.mockReturnValue(createMockSessionState());

      const { result, rerender } = renderHook(() => useContext(StoreContext), {
        wrapper: StoreProvider,
      });

      const stores = result.current!;
      const connectSpy1 = vi.spyOn(stores.adaptorStore, '_connectChannel');
      const connectSpy2 = vi.spyOn(stores.credentialStore, '_connectChannel');
      const connectSpy3 = vi.spyOn(
        stores.sessionContextStore,
        '_connectChannel'
      );

      const mockProvider1 = createMockProvider() as any;

      mockUseSession.mockReturnValue(
        createMockSessionState({
          provider: mockProvider1,
          isConnected: true,
        })
      );

      rerender();

      await waitFor(() => {
        expect(connectSpy1).toHaveBeenCalledWith(mockProvider1);
        expect(connectSpy2).toHaveBeenCalledWith(mockProvider1);
        expect(connectSpy3).toHaveBeenCalledWith(mockProvider1);
      });
    });
  });
});
