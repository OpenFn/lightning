/**
 * useRemoteUsers() Hook Tests
 *
 * Tests the deduplication and connection counting behavior of useRemoteUsers().
 * This hook filters out the local user, deduplicates users by user.id (when they have
 * multiple tabs/clientIds), keeps the latest cursor/selection, and adds connectionCount.
 */

import { act, renderHook } from '@testing-library/react';
import type React from 'react';
import { beforeEach, describe, expect, test } from 'vitest';

import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import {
  useAwareness,
  useRemoteUsers,
} from '../../../js/collaborative-editor/hooks/useAwareness';
import type { AwarenessStoreInstance } from '../../../js/collaborative-editor/stores/createAwarenessStore';
import { createAwarenessStore } from '../../../js/collaborative-editor/stores/createAwarenessStore';
import type {
  AwarenessUser,
  LocalUserData,
} from '../../../js/collaborative-editor/types/awareness';

// =============================================================================
// TEST SETUP & FIXTURES
// =============================================================================

function createWrapper(
  awarenessStore: AwarenessStoreInstance
): React.ComponentType<{ children: React.ReactNode }> {
  const mockStoreValue: StoreContextValue = {
    awarenessStore,
    sessionContextStore:
      {} as unknown as StoreContextValue['sessionContextStore'],
    adaptorStore: {} as unknown as StoreContextValue['adaptorStore'],
    credentialStore: {} as unknown as StoreContextValue['credentialStore'],
    workflowStore: {} as unknown as StoreContextValue['workflowStore'],
    historyStore: {} as unknown as StoreContextValue['historyStore'],
    uiStore: {} as unknown as StoreContextValue['uiStore'],
    editorPreferencesStore:
      {} as unknown as StoreContextValue['editorPreferencesStore'],
  };

  return ({ children }: { children: React.ReactNode }) => (
    <StoreContext.Provider value={mockStoreValue}>
      {children}
    </StoreContext.Provider>
  );
}

function createMockLocalUser(
  overrides: Partial<LocalUserData> = {}
): LocalUserData {
  return {
    id: 'local-user-1',
    name: 'Local User',
    email: 'local@example.com',
    color: '#ff0000',
    ...overrides,
  };
}

function createMockAwarenessUser(
  overrides: Partial<AwarenessUser> = {}
): AwarenessUser {
  return {
    clientId: 100,
    user: {
      id: 'user-1',
      name: 'Test User',
      email: 'test@example.com',
      color: '#00ff00',
    },
    cursor: { x: 100, y: 200 },
    selection: null,
    lastSeen: Date.now(),
    ...overrides,
  };
}

/**
 * Creates a mutable mock awareness instance that can simulate user states
 */
function createMutableMockAwareness() {
  let currentStates = new Map<number, Record<string, unknown>>();

  return {
    getLocalState: () => null,
    setLocalState: () => {},
    setLocalStateField: () => {},
    getStates: () => currentStates,
    on: () => {},
    off: () => {},
    _updateStates: (newStates: Map<number, Record<string, unknown>>) => {
      currentStates = newStates;
    },
  };
}

/**
 * Helper to simulate awareness state changes.
 * This triggers the awareness change handler in the store.
 */
function simulateAwarenessUpdate(
  store: AwarenessStoreInstance,
  users: AwarenessUser[]
): void {
  // Create a map of awareness states keyed by clientId
  const awarenessStates = new Map<number, Record<string, unknown>>();

  users.forEach(user => {
    awarenessStates.set(user.clientId, {
      user: user.user,
      cursor: user.cursor,
      selection: user.selection,
      lastSeen: user.lastSeen,
    });
  });

  // Replace the awareness instance and trigger change handler
  // We need to access the internal handler
  const storeInternal = store as unknown as {
    _internal: { handleAwarenessChange: () => void };
  };

  // Update the raw awareness reference
  const currentState = store.getSnapshot();
  if (currentState.rawAwareness) {
    // Update the mock awareness states
    const mockAwareness = currentState.rawAwareness as unknown as ReturnType<
      typeof createMutableMockAwareness
    >;
    mockAwareness._updateStates(awarenessStates);
  }

  // Trigger the awareness change handler
  storeInternal._internal.handleAwarenessChange();
}

describe('useRemoteUsers()', () => {
  let store: AwarenessStoreInstance;

  beforeEach(() => {
    store = createAwarenessStore();
  });

  // ===========================================================================
  // BASIC FILTERING
  // ===========================================================================

  describe('basic filtering', () => {
    test('returns empty array when no users exist', () => {
      const { result } = renderHook(() => useRemoteUsers(), {
        wrapper: createWrapper(store),
      });

      expect(result.current).toEqual([]);
    });

    test('excludes local user and returns only remote users', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });

      // Create mock awareness and initialize
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useRemoteUsers(), {
        wrapper: createWrapper(store),
      });

      // Initially empty
      expect(result.current).toEqual([]);

      // Add users including one with local user ID
      const localUserAsRemote = createMockAwarenessUser({
        clientId: 99,
        user: {
          id: 'local-user-1',
          name: 'Local User',
          email: 'local@example.com',
          color: '#ff0000',
        },
      });
      const remoteUser1 = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'remote-1',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
      });
      const remoteUser2 = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'remote-2',
          name: 'Bob',
          email: 'bob@example.com',
          color: '#00ff00',
        },
      });

      act(() => {
        simulateAwarenessUpdate(store, [
          localUserAsRemote,
          remoteUser1,
          remoteUser2,
        ]);
      });

      expect(result.current).toHaveLength(2);
      expect(result.current.map(u => u.user.id).sort()).toEqual([
        'remote-1',
        'remote-2',
      ]);
    });

    test('returns all users when localUser is null', () => {
      const user1 = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'user-1',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
      });
      const user2 = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'user-2',
          name: 'Bob',
          email: 'bob@example.com',
          color: '#00ff00',
        },
      });

      // Don't initialize awareness - localUser will be null
      const { result } = renderHook(() => useRemoteUsers(), {
        wrapper: createWrapper(store),
      });

      // Manually set users without initialization
      // Since we can't set users without awareness, we'll initialize with a mock awareness
      const mockAwareness = createMutableMockAwareness();
      act(() => {
        store.initializeAwareness(mockAwareness as never, null as never);
      });

      act(() => {
        simulateAwarenessUpdate(store, [user1, user2]);
      });

      // With null localUser, all users should be returned
      expect(result.current).toHaveLength(2);
      expect(result.current.map(u => u.user.id).sort()).toEqual([
        'user-1',
        'user-2',
      ]);
    });
  });

  // ===========================================================================
  // DEDUPLICATION WITH CONNECTION COUNT
  // ===========================================================================

  describe('deduplication with multiple tabs', () => {
    test('deduplicates user with multiple connections and adds connectionCount', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useRemoteUsers(), {
        wrapper: createWrapper(store),
      });

      // Alice has 3 tabs open (3 different clientIds, same user.id)
      const aliceTab1 = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        cursor: { x: 100, y: 100 },
        lastSeen: 1000,
      });
      const aliceTab2 = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        cursor: { x: 200, y: 200 },
        lastSeen: 2000, // Most recent
      });
      const aliceTab3 = createMockAwarenessUser({
        clientId: 102,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        cursor: { x: 150, y: 150 },
        lastSeen: 1500,
      });

      act(() => {
        simulateAwarenessUpdate(store, [aliceTab1, aliceTab2, aliceTab3]);
      });

      expect(result.current).toHaveLength(1);
      const deduplicatedAlice = result.current[0];

      // Should have connection count of 3
      expect(deduplicatedAlice.connectionCount).toBe(3);

      // Should keep the cursor/selection from the tab with latest lastSeen (tab2)
      expect(deduplicatedAlice.cursor).toEqual({ x: 200, y: 200 });
      expect(deduplicatedAlice.lastSeen).toBe(2000);

      // User data should be preserved
      expect(deduplicatedAlice.user.id).toBe('alice');
      expect(deduplicatedAlice.user.name).toBe('Alice');
    });

    test('handles mix of single and multi-connection users', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useRemoteUsers(), {
        wrapper: createWrapper(store),
      });

      // Alice has 2 connections
      const aliceTab1 = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        lastSeen: 1000,
      });
      const aliceTab2 = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        lastSeen: 2000,
      });

      // Bob has 1 connection
      const bob = createMockAwarenessUser({
        clientId: 102,
        user: {
          id: 'bob',
          name: 'Bob',
          email: 'bob@example.com',
          color: '#00ff00',
        },
        lastSeen: 1500,
      });

      // Charlie has 3 connections
      const charlieTab1 = createMockAwarenessUser({
        clientId: 103,
        user: {
          id: 'charlie',
          name: 'Charlie',
          email: 'charlie@example.com',
          color: '#0000ff',
        },
        lastSeen: 1200,
      });
      const charlieTab2 = createMockAwarenessUser({
        clientId: 104,
        user: {
          id: 'charlie',
          name: 'Charlie',
          email: 'charlie@example.com',
          color: '#0000ff',
        },
        lastSeen: 1800,
      });
      const charlieTab3 = createMockAwarenessUser({
        clientId: 105,
        user: {
          id: 'charlie',
          name: 'Charlie',
          email: 'charlie@example.com',
          color: '#0000ff',
        },
        lastSeen: 2500, // Most recent
      });

      act(() => {
        simulateAwarenessUpdate(store, [
          aliceTab1,
          aliceTab2,
          bob,
          charlieTab1,
          charlieTab2,
          charlieTab3,
        ]);
      });

      expect(result.current).toHaveLength(3);

      const userMap = new Map(result.current.map(u => [u.user.id, u]));

      // Alice: 2 connections, latest lastSeen = 2000
      expect(userMap.get('alice')?.connectionCount).toBe(2);
      expect(userMap.get('alice')?.lastSeen).toBe(2000);

      // Bob: 1 connection
      expect(userMap.get('bob')?.connectionCount).toBe(1);
      expect(userMap.get('bob')?.lastSeen).toBe(1500);

      // Charlie: 3 connections, latest lastSeen = 2500
      expect(userMap.get('charlie')?.connectionCount).toBe(3);
      expect(userMap.get('charlie')?.lastSeen).toBe(2500);
    });

    test('keeps latest cursor position when deduplicating', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useRemoteUsers(), {
        wrapper: createWrapper(store),
      });

      // Alice has 2 tabs, but one has undefined lastSeen
      const aliceTab1 = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        cursor: { x: 100, y: 100 },
        lastSeen: undefined,
      });
      const aliceTab2 = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        cursor: { x: 200, y: 200 },
        lastSeen: 2000,
      });

      act(() => {
        simulateAwarenessUpdate(store, [aliceTab1, aliceTab2]);
      });

      expect(result.current).toHaveLength(1);
      const deduplicatedAlice = result.current[0];

      // Should prefer the one with defined lastSeen
      expect(deduplicatedAlice.lastSeen).toBe(2000);
      expect(deduplicatedAlice.cursor).toEqual({ x: 200, y: 200 });
      expect(deduplicatedAlice.connectionCount).toBe(2);
    });
  });

  // ===========================================================================
  // EDGE CASES
  // ===========================================================================

  describe('edge cases', () => {
    test('handles null cursor and selection gracefully', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useRemoteUsers(), {
        wrapper: createWrapper(store),
      });

      const userWithNullCursor = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'user-1',
          name: 'User 1',
          email: 'user1@example.com',
          color: '#ff0000',
        },
        cursor: null,
        selection: null,
        lastSeen: Date.now(),
      });

      act(() => {
        simulateAwarenessUpdate(store, [userWithNullCursor]);
      });

      expect(result.current).toHaveLength(1);
      expect(result.current[0].cursor).toBeNull();
      expect(result.current[0].selection).toBeNull();
    });

    test('handles user with no lastSeen timestamp', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useRemoteUsers(), {
        wrapper: createWrapper(store),
      });

      const userWithoutLastSeen = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'user-1',
          name: 'User 1',
          email: 'user1@example.com',
          color: '#ff0000',
        },
        lastSeen: undefined,
      });

      act(() => {
        simulateAwarenessUpdate(store, [userWithoutLastSeen]);
      });

      expect(result.current).toHaveLength(1);
      expect(result.current[0].lastSeen).toBeUndefined();
    });

    test('deduplication prefers entry with lastSeen when other has undefined', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useRemoteUsers(), {
        wrapper: createWrapper(store),
      });

      // Two entries for same user, one without lastSeen
      const userTab1 = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'user-1',
          name: 'User 1',
          email: 'user1@example.com',
          color: '#ff0000',
        },
        cursor: { x: 100, y: 100 },
        lastSeen: undefined,
      });

      const userTab2 = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'user-1',
          name: 'User 1',
          email: 'user1@example.com',
          color: '#ff0000',
        },
        cursor: { x: 200, y: 200 },
        lastSeen: 5000,
      });

      act(() => {
        simulateAwarenessUpdate(store, [userTab1, userTab2]);
      });

      expect(result.current).toHaveLength(1);
      expect(result.current[0].lastSeen).toBe(5000);
      expect(result.current[0].cursor).toEqual({ x: 200, y: 200 });
      expect(result.current[0].connectionCount).toBe(2);
    });

    test('sets connectionCount to 1 for single-connection users', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useRemoteUsers(), {
        wrapper: createWrapper(store),
      });

      const bob = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'bob',
          name: 'Bob',
          email: 'bob@example.com',
          color: '#00ff00',
        },
      });

      act(() => {
        simulateAwarenessUpdate(store, [bob]);
      });

      expect(result.current).toHaveLength(1);
      expect(result.current[0].connectionCount).toBe(1);
    });
  });

  // ===========================================================================
  // REACTIVITY
  // ===========================================================================

  describe('reactivity', () => {
    test('updates when users are added or removed', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useRemoteUsers(), {
        wrapper: createWrapper(store),
      });

      // Initially empty
      expect(result.current).toHaveLength(0);

      // Add a user
      const alice = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
      });

      act(() => {
        simulateAwarenessUpdate(store, [alice]);
      });

      expect(result.current).toHaveLength(1);
      expect(result.current[0].user.id).toBe('alice');

      // Add another user
      const bob = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'bob',
          name: 'Bob',
          email: 'bob@example.com',
          color: '#00ff00',
        },
      });

      act(() => {
        simulateAwarenessUpdate(store, [alice, bob]);
      });

      expect(result.current).toHaveLength(2);

      // Remove a user (bob disconnects)
      // Note: Bob will still appear in the cached users list for 60s after disconnect
      act(() => {
        simulateAwarenessUpdate(store, [alice]);
      });

      // Bob is still cached (within 60s TTL), so both users appear
      expect(result.current).toHaveLength(2);
      const userIds = result.current.map(u => u.user.id).sort();
      expect(userIds).toEqual(['alice', 'bob']);
    });
  });
});

// =============================================================================
// NEW UNIFIED useAwareness() API TESTS
// =============================================================================

describe('useAwareness() - unified API with options', () => {
  let store: AwarenessStoreInstance;

  beforeEach(() => {
    store = createAwarenessStore();
  });

  // ===========================================================================
  // DEFAULT BEHAVIOR: cached: false, always excludes local, format: 'array'
  // ===========================================================================

  describe('default behavior (live, always excludes local)', () => {
    test('returns live remote users only (from cursorsMap)', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      // Default behavior: live users only, always excludes local
      const { result } = renderHook(() => useAwareness(), {
        wrapper: createWrapper(store),
      });

      // Add live users
      const alice = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        lastSeen: Date.now(),
      });
      const bob = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'bob',
          name: 'Bob',
          email: 'bob@example.com',
          color: '#00ff00',
        },
        lastSeen: Date.now(),
      });

      act(() => {
        simulateAwarenessUpdate(store, [alice, bob]);
      });

      expect(result.current).toHaveLength(2);
      expect(result.current.map(u => u.user.id).sort()).toEqual([
        'alice',
        'bob',
      ]);
    });

    test('excludes local user from results', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useAwareness(), {
        wrapper: createWrapper(store),
      });

      // Add local user and remote user
      const localUserAsRemote = createMockAwarenessUser({
        clientId: 99,
        user: {
          id: 'local-user-1',
          name: 'Local',
          email: 'local@example.com',
          color: '#ff0000',
        },
      });
      const alice = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
      });

      act(() => {
        simulateAwarenessUpdate(store, [localUserAsRemote, alice]);
      });

      expect(result.current).toHaveLength(1);
      expect(result.current[0].user.id).toBe('alice');
    });

    test('does not deduplicate - shows all clientIds for same user', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      // cached: false means no deduplication - each clientId is separate
      const { result } = renderHook(() => useAwareness(), {
        wrapper: createWrapper(store),
      });

      // Alice with 2 tabs - should show both tabs (no deduplication)
      const aliceTab1 = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        cursor: { x: 100, y: 100 },
        lastSeen: 1000,
      });
      const aliceTab2 = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        cursor: { x: 200, y: 200 },
        lastSeen: 2000,
      });

      act(() => {
        simulateAwarenessUpdate(store, [aliceTab1, aliceTab2]);
      });

      // With cached: false, no deduplication - both tabs appear
      expect(result.current).toHaveLength(2);
      expect(result.current[0].clientId).toBe(100);
      expect(result.current[1].clientId).toBe(101);
    });

    test('does not include recently disconnected users', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      // cached: false means live users only
      const { result } = renderHook(() => useAwareness(), {
        wrapper: createWrapper(store),
      });

      // Add two users
      const alice = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
      });
      const bob = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'bob',
          name: 'Bob',
          email: 'bob@example.com',
          color: '#00ff00',
        },
      });

      act(() => {
        simulateAwarenessUpdate(store, [alice, bob]);
      });

      expect(result.current).toHaveLength(2);

      // Bob disconnects (remove from cursorsMap)
      act(() => {
        simulateAwarenessUpdate(store, [alice]);
      });

      // With cached: false (default), bob should NOT appear (live only)
      expect(result.current).toHaveLength(1);
      expect(result.current[0].user.id).toBe('alice');
    });
  });

  // ===========================================================================
  // OPTION: cached: true
  // ===========================================================================

  describe('cached: true option', () => {
    test('includes recently disconnected users within 60s TTL', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useAwareness({ cached: true }), {
        wrapper: createWrapper(store),
      });

      // Add two users
      const alice = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
      });
      const bob = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'bob',
          name: 'Bob',
          email: 'bob@example.com',
          color: '#00ff00',
        },
      });

      act(() => {
        simulateAwarenessUpdate(store, [alice, bob]);
      });

      // Bob disconnects
      act(() => {
        simulateAwarenessUpdate(store, [alice]);
      });

      // Both users should appear (bob is cached)
      expect(result.current).toHaveLength(2);
      const userIds = result.current.map(u => u.user.id).sort();
      expect(userIds).toEqual(['alice', 'bob']);
    });

    test('deduplicates by user.id and adds connectionCount', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useAwareness({ cached: true }), {
        wrapper: createWrapper(store),
      });

      // Alice with 3 tabs
      const aliceTab1 = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        cursor: { x: 100, y: 100 },
        lastSeen: 1000,
      });
      const aliceTab2 = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        cursor: { x: 200, y: 200 },
        lastSeen: 2000,
      });
      const aliceTab3 = createMockAwarenessUser({
        clientId: 102,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        cursor: { x: 150, y: 150 },
        lastSeen: 1500,
      });

      act(() => {
        simulateAwarenessUpdate(store, [aliceTab1, aliceTab2, aliceTab3]);
      });

      expect(result.current).toHaveLength(1);
      expect(result.current[0].connectionCount).toBe(3);
      expect(result.current[0].cursor).toEqual({ x: 200, y: 200 }); // Latest lastSeen
    });

    test('keeps cursor from latest lastSeen when deduplicating', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useAwareness({ cached: true }), {
        wrapper: createWrapper(store),
      });

      // Alice with 2 tabs, different cursors and timestamps
      const aliceTab1 = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        cursor: { x: 100, y: 100 },
        lastSeen: 1000,
      });
      const aliceTab2 = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        cursor: { x: 500, y: 600 },
        lastSeen: 3000, // Latest
      });

      act(() => {
        simulateAwarenessUpdate(store, [aliceTab1, aliceTab2]);
      });

      expect(result.current).toHaveLength(1);
      expect(result.current[0].cursor).toEqual({ x: 500, y: 600 });
      expect(result.current[0].lastSeen).toBe(3000);
    });
  });

  // ===========================================================================
  // OPTION: format: 'map'
  // ===========================================================================

  describe('format: map option', () => {
    test('returns Map<clientId, AwarenessUser>', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useAwareness({ format: 'map' }), {
        wrapper: createWrapper(store),
      });

      const alice = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
      });
      const bob = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'bob',
          name: 'Bob',
          email: 'bob@example.com',
          color: '#00ff00',
        },
      });

      act(() => {
        simulateAwarenessUpdate(store, [alice, bob]);
      });

      expect(result.current).toBeInstanceOf(Map);
      expect(result.current.size).toBe(2);
      expect(result.current.get(100)?.user.id).toBe('alice');
      expect(result.current.get(101)?.user.id).toBe('bob');
    });

    test('always excludes local user when format is map', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      // Always excludes local user
      const { result } = renderHook(() => useAwareness({ format: 'map' }), {
        wrapper: createWrapper(store),
      });

      const localUserAsRemote = createMockAwarenessUser({
        clientId: 99,
        user: {
          id: 'local-user-1',
          name: 'Local',
          email: 'local@example.com',
          color: '#ff0000',
        },
      });
      const alice = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
      });

      act(() => {
        simulateAwarenessUpdate(store, [localUserAsRemote, alice]);
      });

      // Local user should be excluded
      expect(result.current.size).toBe(1);
      expect(result.current.has(99)).toBe(false);
      expect(result.current.get(100)?.user.id).toBe('alice');
    });

    test('works with cached mode when format is map', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(
        () => useAwareness({ format: 'map', cached: true }),
        { wrapper: createWrapper(store) }
      );

      const alice = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
      });

      act(() => {
        simulateAwarenessUpdate(store, [alice]);
      });

      expect(result.current.size).toBe(1);
      expect(result.current.get(100)?.user.id).toBe('alice');

      // Alice disconnects
      act(() => {
        simulateAwarenessUpdate(store, []);
      });

      // With cached: true, alice should still appear
      expect(result.current.size).toBe(1);
      expect(result.current.get(100)?.user.id).toBe('alice');
    });
  });

  // ===========================================================================
  // OPTION COMBINATIONS
  // ===========================================================================

  describe('option combinations', () => {
    test('cached: true + format: map', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(
        () => useAwareness({ cached: true, format: 'map' }),
        { wrapper: createWrapper(store) }
      );

      // Alice with 2 tabs - should be deduplicated
      const aliceTab1 = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        cursor: { x: 100, y: 100 },
        lastSeen: 1000,
      });
      const aliceTab2 = createMockAwarenessUser({
        clientId: 101,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
        cursor: { x: 200, y: 200 },
        lastSeen: 2000,
      });
      const bob = createMockAwarenessUser({
        clientId: 102,
        user: {
          id: 'bob',
          name: 'Bob',
          email: 'bob@example.com',
          color: '#00ff00',
        },
      });

      act(() => {
        simulateAwarenessUpdate(store, [aliceTab1, aliceTab2, bob]);
      });

      expect(result.current).toBeInstanceOf(Map);
      expect(result.current.size).toBe(2);

      // Convert Map to array to verify contents
      const usersArray = Array.from(result.current.values());
      const userMap = new Map(usersArray.map(u => [u.user.id, u]));

      // Should be deduplicated - alice should have connectionCount of 2
      const aliceResult = userMap.get('alice');
      expect(aliceResult?.user.id).toBe('alice');
      expect(aliceResult?.connectionCount).toBe(2);
      expect(aliceResult?.cursor).toEqual({ x: 200, y: 200 }); // Latest cursor
      expect(aliceResult?.lastSeen).toBe(2000);

      // Bob should have connectionCount of 1
      const bobResult = userMap.get('bob');
      expect(bobResult?.user.id).toBe('bob');
      expect(bobResult?.connectionCount).toBe(1);
    });
  });

  // ===========================================================================
  // EDGE CASES
  // ===========================================================================

  describe('edge cases', () => {
    test('returns empty array when no users and no options specified', () => {
      const { result } = renderHook(() => useAwareness(), {
        wrapper: createWrapper(store),
      });

      expect(result.current).toEqual([]);
    });

    test('returns empty Map when format: map and no users', () => {
      const { result } = renderHook(() => useAwareness({ format: 'map' }), {
        wrapper: createWrapper(store),
      });

      expect(result.current).toBeInstanceOf(Map);
      expect(result.current.size).toBe(0);
    });

    test('handles null localUser (includes all users when local is null)', () => {
      const mockAwareness = createMutableMockAwareness();

      // Initialize with null local user
      act(() => {
        store.initializeAwareness(mockAwareness as never, null as never);
      });

      const { result } = renderHook(() => useAwareness(), {
        wrapper: createWrapper(store),
      });

      const alice = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
      });

      act(() => {
        simulateAwarenessUpdate(store, [alice]);
      });

      // Should include alice since localUser is null
      expect(result.current).toHaveLength(1);
      expect(result.current[0].user.id).toBe('alice');
    });

    test('returns consistent data across multiple calls', () => {
      const localUser = createMockLocalUser({ id: 'local-user-1' });
      const mockAwareness = createMutableMockAwareness();

      act(() => {
        store.initializeAwareness(mockAwareness as never, localUser);
      });

      const { result } = renderHook(() => useAwareness(), {
        wrapper: createWrapper(store),
      });

      const alice = createMockAwarenessUser({
        clientId: 100,
        user: {
          id: 'alice',
          name: 'Alice',
          email: 'alice@example.com',
          color: '#ff0000',
        },
      });

      act(() => {
        simulateAwarenessUpdate(store, [alice]);
      });

      // Data should be consistent
      expect(result.current).toHaveLength(1);
      expect(result.current[0].user.id).toBe('alice');
    });
  });
});
