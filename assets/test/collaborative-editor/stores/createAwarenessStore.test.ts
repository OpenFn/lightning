import { describe, expect, test, vi } from 'vitest';
import { Awareness } from 'y-protocols/awareness';
import * as Y from 'yjs';

import { createAwarenessStore } from '../../../js/collaborative-editor/stores/createAwarenessStore';
import type {
  ActivityState,
  LocalUserData,
} from '../../../js/collaborative-editor/types/awareness';

function createMockLocalUser(
  overrides: Partial<LocalUserData> = {}
): LocalUserData {
  return {
    id: `user-${Math.random().toString(36).substring(7)}`,
    name: 'Test User',
    email: 'test@example.com',
    color: '#ff0000',
    ...overrides,
  };
}

describe('AwarenessStore - Activity State Tracking', () => {
  test('tracks lastState field in awareness users', () => {
    const store = createAwarenessStore();
    const ydoc = new Y.Doc();
    const awareness = new Awareness(ydoc);
    const localUser = createMockLocalUser({ id: 'local-user' });

    store.initializeAwareness(awareness, localUser);

    // Add a remote user with lastState
    const remoteClientId = 123;
    const states = new Map();
    states.set(remoteClientId, {
      user: {
        id: 'remote-user',
        name: 'Remote User',
        email: 'remote@example.com',
        color: '#00ff00',
      },
      lastState: 'active' as ActivityState,
    });

    awareness.states = states;
    awareness.emit('change', []);

    const state = store.getSnapshot();
    const remoteUser = state.users.find(u => u.user.id === 'remote-user');

    expect(remoteUser?.lastState).toBe('active');
  });

  test('updates user when lastState changes', () => {
    const store = createAwarenessStore();
    const ydoc = new Y.Doc();
    const awareness = new Awareness(ydoc);
    const localUser = createMockLocalUser({ id: 'local-user' });

    store.initializeAwareness(awareness, localUser);

    const remoteClientId = 123;

    // First update - active state
    const states1 = new Map();
    states1.set(remoteClientId, {
      user: {
        id: 'remote-user',
        name: 'Remote User',
        email: 'remote@example.com',
        color: '#00ff00',
      },
      lastState: 'active' as ActivityState,
    });
    awareness.states = states1;
    awareness.emit('change', []);

    const state1 = store.getSnapshot();
    const user1 = state1.cursorsMap.get(remoteClientId);
    expect(user1?.lastState).toBe('active');

    // Second update - away state
    const states2 = new Map();
    states2.set(remoteClientId, {
      user: {
        id: 'remote-user',
        name: 'Remote User',
        email: 'remote@example.com',
        color: '#00ff00',
      },
      lastState: 'away' as ActivityState,
    });
    awareness.states = states2;
    awareness.emit('change', []);

    const state2 = store.getSnapshot();
    const user2 = state2.cursorsMap.get(remoteClientId);

    // Should be different references due to state change
    expect(user1).not.toBe(user2);
    expect(user2?.lastState).toBe('away');
  });

  test('maintains referential stability when lastState unchanged', () => {
    const store = createAwarenessStore();
    const ydoc = new Y.Doc();
    const awareness = new Awareness(ydoc);
    const localUser = createMockLocalUser({ id: 'local-user' });

    store.initializeAwareness(awareness, localUser);

    const remoteClientId = 123;
    const remoteUserState = {
      user: {
        id: 'remote-user',
        name: 'Remote User',
        email: 'remote@example.com',
        color: '#00ff00',
      },
      lastState: 'active' as ActivityState,
    };

    // First update
    const states1 = new Map();
    states1.set(remoteClientId, remoteUserState);
    awareness.states = states1;
    awareness.emit('change', []);

    const state1 = store.getSnapshot();
    const user1 = state1.cursorsMap.get(remoteClientId);

    // Second update with same data
    const states2 = new Map();
    states2.set(remoteClientId, remoteUserState);
    awareness.states = states2;
    awareness.emit('change', []);

    const state2 = store.getSnapshot();
    const user2 = state2.cursorsMap.get(remoteClientId);

    // Should maintain referential stability (Immer won't create new object)
    expect(user1).toBe(user2);
  });

  test('handles undefined lastState gracefully', () => {
    const store = createAwarenessStore();
    const ydoc = new Y.Doc();
    const awareness = new Awareness(ydoc);
    const localUser = createMockLocalUser({ id: 'local-user' });

    store.initializeAwareness(awareness, localUser);

    const remoteClientId = 123;
    const states = new Map();
    states.set(remoteClientId, {
      user: {
        id: 'remote-user',
        name: 'Remote User',
        email: 'remote@example.com',
        color: '#00ff00',
      },
      // lastState intentionally omitted
    });

    awareness.states = states;
    awareness.emit('change', []);

    const state = store.getSnapshot();
    const remoteUser = state.users.find(u => u.user.id === 'remote-user');

    // Should handle missing lastState without errors
    expect(remoteUser).toBeDefined();
    expect(remoteUser?.lastState).toBeUndefined();
  });

  test('supports all activity states: active, away, idle', () => {
    const store = createAwarenessStore();
    const ydoc = new Y.Doc();
    const awareness = new Awareness(ydoc);
    const localUser = createMockLocalUser({ id: 'local-user' });

    store.initializeAwareness(awareness, localUser);

    const states = new Map();
    states.set(1, {
      user: {
        id: 'user-1',
        name: 'Active User',
        email: 'active@example.com',
        color: '#ff0000',
      },
      lastState: 'active' as ActivityState,
    });
    states.set(2, {
      user: {
        id: 'user-2',
        name: 'Away User',
        email: 'away@example.com',
        color: '#00ff00',
      },
      lastState: 'away' as ActivityState,
    });
    states.set(3, {
      user: {
        id: 'user-3',
        name: 'Idle User',
        email: 'idle@example.com',
        color: '#0000ff',
      },
      lastState: 'idle' as ActivityState,
    });

    awareness.states = states;
    awareness.emit('change', []);

    const state = store.getSnapshot();

    const activeUser = state.users.find(u => u.user.id === 'user-1');
    const awayUser = state.users.find(u => u.user.id === 'user-2');
    const idleUser = state.users.find(u => u.user.id === 'user-3');

    expect(activeUser?.lastState).toBe('active');
    expect(awayUser?.lastState).toBe('away');
    expect(idleUser?.lastState).toBe('idle');
  });
});

describe('AwarenessStore - Visibility API Integration', () => {
  test('initActivityStateChange sets up visibility listener', () => {
    const store = createAwarenessStore();
    const setStateMock = vi.fn();

    store._internal.initActivityStateChange(setStateMock);

    // Initial call should happen
    expect(setStateMock).toHaveBeenCalled();
  });

  test('calls setState with away when document is hidden', () => {
    const store = createAwarenessStore();

    // Mock document visibility as hidden
    Object.defineProperty(document, 'hidden', {
      configurable: true,
      get: () => true,
    });

    const setStateMock = vi.fn();
    store._internal.initActivityStateChange(setStateMock);

    // Should be called with 'away' when document is hidden
    expect(setStateMock).toHaveBeenCalledWith('away');
  });

  test('calls setState with active when document is visible', () => {
    const store = createAwarenessStore();

    // Mock document visibility as visible
    Object.defineProperty(document, 'hidden', {
      configurable: true,
      get: () => false,
    });

    const setStateMock = vi.fn();
    store._internal.initActivityStateChange(setStateMock);

    // Should be called with 'active' when document is visible
    expect(setStateMock).toHaveBeenCalledWith('active');
  });

  test('handles missing visibility API gracefully', () => {
    const store = createAwarenessStore();
    const setStateMock = vi.fn();

    expect(() => {
      store._internal.initActivityStateChange(setStateMock);
    }).not.toThrow();
  });
});
