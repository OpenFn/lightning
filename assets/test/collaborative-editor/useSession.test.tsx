/**
 * useSession Hook Tests
 *
 * Tests for the useSession hook that provides access to the SessionStore instance.
 * Focuses on behavioral coverage of hook functionality:
 * - Basic functionality and context validation
 * - Core reactivity (store updates propagate to hooks)
 * - Edge cases and error handling
 */

import { act, renderHook, waitFor } from '@testing-library/react';
import type React from 'react';
import { useEffect, useState } from 'react';
import { afterEach, beforeEach, describe, expect, test } from 'vitest';

import { useSession } from '../../js/collaborative-editor/hooks/useSession';
import type { SessionStoreInstance } from '../../js/collaborative-editor/stores/createSessionStore';
import { createSessionStore } from '../../js/collaborative-editor/stores/createSessionStore';

import { SessionContext } from '../../js/collaborative-editor/contexts/SessionProvider';
import { createMockSocket } from './mocks/phoenixSocket';

// =============================================================================
// TEST HELPERS
// =============================================================================

/**
 * Creates a wrapper component with SessionProvider context
 * Returns both the wrapper and the store instance for test manipulation
 */
function createWrapper() {
  const store = createSessionStore();
  const mockSocket = createMockSocket();

  // Initialize the session store
  store.initializeSession(mockSocket, 'test:room', {
    id: 'user-1',
    name: 'Test User',
    color: '#ff0000',
  });

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider
      value={{ sessionStore: store, isNewWorkflow: false }}
    >
      {children}
    </SessionContext.Provider>
  );

  return { wrapper, store };
}

/**
 * Creates a wrapper without initializing the session
 * Useful for testing pre-initialization state
 */
function createUninitializedWrapper() {
  const store = createSessionStore();

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider
      value={{ sessionStore: store, isNewWorkflow: false }}
    >
      {children}
    </SessionContext.Provider>
  );

  return { wrapper, store };
}

// =============================================================================
// BASIC HOOK FUNCTIONALITY TESTS
// =============================================================================

describe('useSession', () => {
  describe('basic functionality', () => {
    test('returns session state with default and custom selectors', () => {
      const { wrapper, store } = createWrapper();

      // Test default selector returns full state
      const { result: fullResult } = renderHook(() => useSession(), {
        wrapper,
      });
      const storeSnapshot = store.getSnapshot();
      expect(fullResult.current).toEqual(storeSnapshot);
      expect(fullResult.current.ydoc).toBeDefined();
      expect(fullResult.current.provider).toBeDefined();
      expect(fullResult.current.awareness).toBeDefined();

      // Test custom selector returns specific data types
      const { result: ydocResult } = renderHook(
        () => useSession(state => state.ydoc),
        { wrapper }
      );
      expect(ydocResult.current).toBeDefined();
      expect(ydocResult.current.constructor.name).toBe('Doc');

      const { result: primitiveResult } = renderHook(
        () => useSession(state => state.isConnected),
        { wrapper }
      );
      expect(typeof primitiveResult.current).toBe('boolean');

      const { result: objectResult } = renderHook(
        () =>
          useSession(state => ({
            isConnected: state.isConnected,
            isSynced: state.isSynced,
          })),
        { wrapper }
      );
      expect(objectResult.current).toEqual({
        isConnected: expect.any(Boolean),
        isSynced: expect.any(Boolean),
      });
    });

    test('throws error when used outside provider', () => {
      // renderHook without wrapper means no SessionProvider
      expect(() => {
        renderHook(() => useSession());
      }).toThrow('useSession must be used within a SessionProvider');
    });

    test('throws error with helpful message outside provider', () => {
      try {
        renderHook(() => useSession());
        expect.fail('Should have thrown error');
      } catch (error: unknown) {
        expect((error as Error).message).toContain(
          'useSession must be used within a SessionProvider'
        );
      }
    });
  });

  // =============================================================================
  // REACTIVITY TESTS
  // =============================================================================

  describe('reactivity', () => {
    test('hook updates when store changes', async () => {
      const { wrapper, store } = createUninitializedWrapper();

      const { result } = renderHook(
        () => useSession(state => state.isConnected),
        { wrapper }
      );

      expect(result.current).toBe(false);

      // Initialize session which should trigger connection
      const mockSocket = createMockSocket();
      store.initializeSession(mockSocket, 'test:room', {
        id: 'user-1',
        name: 'Test User',
        color: '#ff0000',
      });

      await waitFor(() => {
        expect(result.current).toBe(true);
      });
    });

    test('multiple hooks share same state', () => {
      const { wrapper } = createWrapper();

      const { result: result1 } = renderHook(
        () => useSession(state => state.ydoc),
        { wrapper }
      );

      const { result: result2 } = renderHook(
        () => useSession(state => state.ydoc),
        { wrapper }
      );

      // Both hooks should return the same ydoc instance
      expect(result1.current).toBe(result2.current);
    });
  });

  // =============================================================================
  // ERROR HANDLING TESTS
  // =============================================================================

  describe('error handling', () => {
    test('handles rapid state updates', async () => {
      const { wrapper, store } = createWrapper();

      const { result } = renderHook(() => useSession(state => state.isSynced), {
        wrapper,
      });

      // Trigger multiple rapid updates by destroying and reinitializing
      const mockSocket = createMockSocket();
      for (let i = 0; i < 5; i++) {
        store.initializeSession(mockSocket, `test:room-${i}`, {
          id: `user-${i}`,
          name: `Test User ${i}`,
          color: '#ff0000',
        });
      }

      // Should handle all updates without error
      await waitFor(() => {
        expect(result.current).toBeDefined();
      });
    });

    test('handles null values before initialization', () => {
      const { wrapper, store } = createUninitializedWrapper();

      const { result } = renderHook(() => useSession(), { wrapper });

      // Before initialization, some values should be null
      expect(result.current.ydoc).toBeNull();
      expect(result.current.provider).toBeNull();
      expect(result.current.awareness).toBeNull();
      expect(store).toBeDefined();
    });

    test('handles undefined selector result', () => {
      const { wrapper } = createWrapper();

      const { result } = renderHook(
        () => useSession(state => (state as any).nonExistentProperty),
        { wrapper }
      );

      expect(result.current).toBeUndefined();
    });

    test('selector throws error is handled gracefully', () => {
      const { wrapper } = createWrapper();

      const faultySelector = () => {
        throw new Error('Selector error');
      };

      expect(() => {
        renderHook(() => useSession(faultySelector), { wrapper });
      }).toThrow('Selector error');
    });
  });

  // =============================================================================
  // INTEGRATION TESTS
  // =============================================================================

  describe('integration', () => {
    test('works with store initialization and updates', async () => {
      const { wrapper, store } = createWrapper();

      const { result } = renderHook(() => useSession(), { wrapper });

      expect(result.current.ydoc).toBeDefined();
      expect(result.current.provider).toBeDefined();
      expect(result.current.awareness).toBeDefined();
      expect(store.isReady()).toBe(true);
    });

    test('provider updates propagate to hook', async () => {
      const { wrapper, store } = createUninitializedWrapper();

      const { result } = renderHook(() => useSession(), { wrapper });

      expect(result.current.provider).toBeNull();

      const mockSocket = createMockSocket();
      act(() => {
        store.initializeSession(mockSocket, 'test:room', {
          id: 'user-1',
          name: 'Test User',
          color: '#ff0000',
        });
      });

      await waitFor(() => {
        expect(result.current.provider).not.toBeNull();
      });
    });

    test('store destroy cleans up state', async () => {
      const { wrapper, store } = createWrapper();

      const { result, unmount } = renderHook(() => useSession(), { wrapper });

      expect(result.current.ydoc).toBeDefined();

      act(() => {
        store.destroy();
      });

      await waitFor(() => {
        expect(result.current.ydoc).toBeNull();
      });

      unmount();
    });

    test('hook works with component state and effects', async () => {
      const { wrapper } = createWrapper();

      function useSessionWithLocalState() {
        const session = useSession();
        const [count, setCount] = useState(0);

        useEffect(() => {
          if (session.isConnected) {
            setCount(c => c + 1);
          }
        }, [session.isConnected]);

        return { session, count };
      }

      const { result } = renderHook(() => useSessionWithLocalState(), {
        wrapper,
      });

      await waitFor(() => {
        expect(result.current.count).toBeGreaterThan(0);
      });

      expect(result.current.session).toBeDefined();
    });

    test('hook works with conditional rendering', () => {
      const { wrapper } = createWrapper();

      function useConditionalSession(enabled: boolean) {
        const session = useSession();
        if (!enabled) {
          return null;
        }
        return session;
      }

      const { result, rerender } = renderHook(
        ({ enabled }) => useConditionalSession(enabled),
        {
          wrapper,
          initialProps: { enabled: false },
        }
      );

      expect(result.current).toBeNull();

      rerender({ enabled: true });

      expect(result.current).toBeDefined();
      expect(result.current!.ydoc).toBeDefined();
    });
  });
});
