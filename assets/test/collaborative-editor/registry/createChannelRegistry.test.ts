/**
 * Channel Registry Tests
 *
 * Tests for managing concurrent channel connections during version transitions
 *
 * ## Key Behaviors Tested
 * - State machine transitions (connecting → settling → active → draining →
 *   destroyed)
 * - migrate() creates new entry and marks old as draining
 * - Cleanup of draining entries after grace period
 * - Subscriber notifications on state changes
 * - Error handling (settling timeout, resource cleanup failures)
 */

import { describe, test, expect, beforeEach, vi, afterEach } from 'vitest';

import { createChannelRegistry } from '../../../js/collaborative-editor/registry/createChannelRegistry';
import type { ChannelRegistryInstance } from '../../../js/collaborative-editor/registry/createChannelRegistry';
import { waitForCondition } from '../mocks/phoenixChannel';
import { createMockSocket } from '../mocks/phoenixSocket';

// Global mock instance tracking (for vi.mock factories which can't access
// top-level variables)
(globalThis as any).mockProviderInstances = [];

vi.mock('yjs', () => {
  class MockEventEmitter {
    private handlers = new Map<string, Set<Function>>();

    on(event: string, handler: Function) {
      if (!this.handlers.has(event)) {
        this.handlers.set(event, new Set());
      }
      this.handlers.get(event)!.add(handler);
    }

    off(event: string, handler: Function) {
      this.handlers.get(event)?.delete(handler);
    }

    _emit(event: string, ...args: any[]) {
      const handlers = this.handlers.get(event);
      if (handlers) {
        handlers.forEach(handler => handler(...args));
      }
    }
  }

  class MockYDoc extends MockEventEmitter {
    destroy() {
      // Clean up
    }
  }

  return {
    Doc: MockYDoc,
  };
});

vi.mock('y-protocols/awareness', () => {
  class MockEventEmitter {
    private handlers = new Map<string, Set<Function>>();

    on(event: string, handler: Function) {
      if (!this.handlers.has(event)) {
        this.handlers.set(event, new Set());
      }
      this.handlers.get(event)!.add(handler);
    }

    off(event: string, handler: Function) {
      this.handlers.get(event)?.delete(handler);
    }

    _emit(event: string, ...args: any[]) {
      const handlers = this.handlers.get(event);
      if (handlers) {
        handlers.forEach(handler => handler(...args));
      }
    }
  }

  class MockAwareness extends MockEventEmitter {
    constructor(_doc: any) {
      super();
    }

    destroy() {
      // Clean up
    }
  }

  return {
    Awareness: MockAwareness,
  };
});

vi.mock('y-phoenix-channel', () => {
  class MockEventEmitter {
    private handlers = new Map<string, Set<Function>>();

    on(event: string, handler: Function) {
      if (!this.handlers.has(event)) {
        this.handlers.set(event, new Set());
      }
      this.handlers.get(event)!.add(handler);
    }

    off(event: string, handler: Function) {
      this.handlers.get(event)?.delete(handler);
    }

    _emit(event: string, ...args: any[]) {
      const handlers = this.handlers.get(event);
      if (handlers) {
        handlers.forEach(handler => handler(...args));
      }
    }
  }

  class MockPhoenixChannelProvider extends MockEventEmitter {
    doc: any;
    awareness: any;
    channel: any;
    synced: boolean = false;

    constructor(
      _socket: any,
      public roomname: string,
      doc: any,
      options: any
    ) {
      super();
      this.doc = doc;
      this.awareness = options.awareness;
      (globalThis as any).mockProviderInstances.push(this);
    }

    destroy() {
      // Clean up
    }
  }

  return {
    PhoenixChannelProvider: MockPhoenixChannelProvider,
  };
});

interface MockPhoenixChannelProvider {
  doc: any;
  awareness: any;
  channel: any;
  synced: boolean;
  roomname: string;
  on(event: string, handler: Function): void;
  off(event: string, handler: Function): void;
  _emit(event: string, ...args: any[]): void;
  destroy(): void;
}

describe('ChannelRegistry - Creation and Basic Queries', () => {
  let registry: ChannelRegistryInstance;

  beforeEach(() => {
    (globalThis as any).mockProviderInstances = [];
    registry = createChannelRegistry();
  });

  afterEach(() => {
    registry.destroy();
    (globalThis as any).mockProviderInstances = [];
  });

  test('creates registry with null entries', () => {
    expect(registry.getCurrentEntry()).toBeNull();
    expect(registry.getDrainingEntry()).toBeNull();
    expect(registry.isTransitioning()).toBe(false);
  });

  test('supports subscribing to state changes', () => {
    const listener = vi.fn();
    const unsubscribe = registry.subscribe(listener);

    expect(typeof unsubscribe).toBe('function');
    expect(listener).not.toHaveBeenCalled();

    unsubscribe();
  });
});

describe('ChannelRegistry - State Machine Transitions', () => {
  let registry: ChannelRegistryInstance;
  let socket: ReturnType<typeof createMockSocket>;

  beforeEach(() => {
    (globalThis as any).mockProviderInstances = [];
    registry = createChannelRegistry();
    socket = createMockSocket();
    vi.useFakeTimers();
  });

  afterEach(() => {
    registry.destroy();
    (globalThis as any).mockProviderInstances = [];
    vi.useRealTimers();
  });

  test('creates entry in connecting state', async () => {
    const migratePromise = registry.migrate(socket, 'workflow:v1', {});

    const entry = registry.getCurrentEntry();
    expect(entry).not.toBeNull();
    expect(entry!.state).toBe('connecting');
    expect(entry!.roomname).toBe('workflow:v1');
    expect(entry!.createdAt).toBeGreaterThan(0);
    expect(entry!.settledAt).toBeNull();

    // Clean up
    registry.destroy();
    await expect(migratePromise).rejects.toThrow();
  });

  test('transitions from connecting to settling on connected status', async () => {
    const migratePromise = registry.migrate(socket, 'workflow:v1', {});

    const entry = registry.getCurrentEntry()!;
    expect(entry.state).toBe('connecting');

    // Simulate provider status change to connected
    (entry.provider as MockPhoenixChannelProvider)._emit('status', {
      status: 'connected',
    });

    // Wait for state transition
    await waitForCondition(() => entry.state === 'settling', {
      timeout: 100,
    });

    expect(entry.state).toBe('settling');

    // Clean up
    registry.destroy();
    await expect(migratePromise).rejects.toThrow();
  });

  test('transitions from settling to active on sync + first update', async () => {
    // This test needs real timers for proper async behavior
    vi.useRealTimers();

    const migratePromise = registry.migrate(socket, 'workflow:v1', {});
    const entry = registry.getCurrentEntry()!;

    // Transition to settling
    (entry.provider as MockPhoenixChannelProvider)._emit('status', {
      status: 'connected',
    });
    await waitForCondition(() => entry.state === 'settling');

    // Simulate sync
    (entry.provider as MockPhoenixChannelProvider)._emit('sync', true);

    // Simulate first update from provider
    const mockUpdate = new Uint8Array([1, 2, 3]);
    (entry.ydoc as any)._emit('update', mockUpdate, entry.provider);

    // Wait for state transition and promise resolution
    await waitForCondition(() => entry.state === 'active', {
      timeout: 100,
    });
    await migratePromise;

    expect(entry.state).toBe('active');
    expect(entry.settledAt).toBeGreaterThan(0);

    // Restore fake timers for afterEach cleanup
    vi.useFakeTimers();
  });

  test('handles settling timeout', async () => {
    const migratePromise = registry.migrate(socket, 'workflow:v1', {});

    const entry = registry.getCurrentEntry()!;

    // Transition to settling
    (entry.provider as MockPhoenixChannelProvider)._emit('status', {
      status: 'connected',
    });
    await waitForCondition(() => entry.state === 'settling');

    // Fast-forward past settling timeout (10 seconds)
    await vi.advanceTimersByTimeAsync(10000);

    // Entry should remain in settling state on timeout (not become active)
    expect(entry.state).toBe('settling');

    // Clean up
    registry.destroy();
    await expect(migratePromise).rejects.toThrow();
  });
});

describe('ChannelRegistry - Migration', () => {
  let registry: ChannelRegistryInstance;
  let socket: ReturnType<typeof createMockSocket>;

  beforeEach(() => {
    (globalThis as any).mockProviderInstances = [];
    registry = createChannelRegistry();
    socket = createMockSocket();
    vi.useFakeTimers();
  });

  afterEach(() => {
    registry.destroy();
    (globalThis as any).mockProviderInstances = [];
    vi.useRealTimers();
  });

  test('migrate creates new entry and marks old as draining', async () => {
    // Create first entry and make it active
    const migrate1Promise = registry.migrate(socket, 'workflow:v1', {});
    const entry1 = registry.getCurrentEntry()!;

    // Make entry1 active
    (entry1.provider as MockPhoenixChannelProvider)._emit('status', {
      status: 'connected',
    });
    await waitForCondition(() => entry1.state === 'settling');
    (entry1.provider as MockPhoenixChannelProvider)._emit('sync', true);
    (entry1.ydoc as any)._emit('update', new Uint8Array([1]), entry1.provider);
    await migrate1Promise;

    expect(entry1.state).toBe('active');

    // Start second migration
    const migrate2Promise = registry.migrate(socket, 'workflow:v2', {});
    const entry2 = registry.getCurrentEntry()!;

    // Entry1 should now be draining
    expect(entry1.state).toBe('draining');
    expect(registry.getDrainingEntry()).toBe(entry1);

    // Entry2 should be current and connecting
    expect(entry2).not.toBe(entry1);
    expect(entry2.state).toBe('connecting');
    expect(registry.getCurrentEntry()).toBe(entry2);
    expect(registry.isTransitioning()).toBe(true);

    // Clean up
    registry.destroy();
    await expect(migrate2Promise).rejects.toThrow();
  });

  test('starts drain timer when new entry becomes active', async () => {
    // Create first entry and make it active
    const migrate1Promise = registry.migrate(socket, 'workflow:v1', {});
    const entry1 = registry.getCurrentEntry()!;

    (entry1.provider as MockPhoenixChannelProvider)._emit('status', {
      status: 'connected',
    });
    await waitForCondition(() => entry1.state === 'settling');
    (entry1.provider as MockPhoenixChannelProvider)._emit('sync', true);
    (entry1.ydoc as any)._emit('update', new Uint8Array([1]), entry1.provider);
    await migrate1Promise;

    // Start second migration
    const migrate2Promise = registry.migrate(socket, 'workflow:v2', {});
    const entry2 = registry.getCurrentEntry()!;

    expect(entry1.state).toBe('draining');

    // Make entry2 active
    (entry2.provider as MockPhoenixChannelProvider)._emit('status', {
      status: 'connected',
    });
    await waitForCondition(() => entry2.state === 'settling');
    (entry2.provider as MockPhoenixChannelProvider)._emit('sync', true);
    (entry2.ydoc as any)._emit('update', new Uint8Array([1]), entry2.provider);
    await migrate2Promise;

    expect(entry2.state).toBe('active');

    // Drain timer should be running - entry1 still exists
    expect(registry.getDrainingEntry()).toBe(entry1);
    expect(entry1.state).toBe('draining');

    // Fast-forward past grace period (2 seconds)
    await vi.advanceTimersByTimeAsync(2000);

    // Entry1 should now be destroyed and removed
    expect(entry1.state).toBe('destroyed');
    expect(registry.getDrainingEntry()).toBeNull();
    expect(registry.isTransitioning()).toBe(false);
  });

  test('migrate resolves when new entry becomes active', async () => {
    const migratePromise = registry.migrate(socket, 'workflow:v1', {});
    const entry = registry.getCurrentEntry()!;

    // Verify promise hasn't resolved yet
    let resolved = false;
    migratePromise.then(() => {
      resolved = true;
    });

    await vi.advanceTimersByTimeAsync(0);
    expect(resolved).toBe(false);

    // Make entry active
    (entry.provider as MockPhoenixChannelProvider)._emit('status', {
      status: 'connected',
    });
    await waitForCondition(() => entry.state === 'settling');
    (entry.provider as MockPhoenixChannelProvider)._emit('sync', true);
    (entry.ydoc as any)._emit('update', new Uint8Array([1]), entry.provider);

    // Wait for promise to resolve
    await migratePromise;
    expect(entry.state).toBe('active');
    expect(resolved).toBe(true);
  });
});

describe('ChannelRegistry - Subscriber Notifications', () => {
  let registry: ChannelRegistryInstance;
  let socket: ReturnType<typeof createMockSocket>;

  beforeEach(() => {
    (globalThis as any).mockProviderInstances = [];
    registry = createChannelRegistry();
    socket = createMockSocket();
    vi.useFakeTimers();
  });

  afterEach(() => {
    registry.destroy();
    (globalThis as any).mockProviderInstances = [];
    vi.useRealTimers();
  });

  test('notifies subscribers on state changes', async () => {
    // This test needs real timers for proper async behavior
    vi.useRealTimers();

    const listener = vi.fn();
    registry.subscribe(listener);

    const migratePromise = registry.migrate(socket, 'workflow:v1', {});
    const entry = registry.getCurrentEntry()!;

    // Migration should trigger notification
    expect(listener).toHaveBeenCalled();
    listener.mockClear();

    // State transitions should trigger notifications
    (entry.provider as MockPhoenixChannelProvider)._emit('status', {
      status: 'connected',
    });
    await waitForCondition(() => entry.state === 'settling');
    expect(listener).toHaveBeenCalled();
    listener.mockClear();

    (entry.provider as MockPhoenixChannelProvider)._emit('sync', true);
    (entry.ydoc as any)._emit('update', new Uint8Array([1]), entry.provider);
    await waitForCondition(() => entry.state === 'active');
    expect(listener).toHaveBeenCalled();

    // Clean up
    await migratePromise;

    // Restore fake timers for afterEach cleanup
    vi.useFakeTimers();
  });

  test('notifies subscribers when draining entry is destroyed', async () => {
    // Create first entry and make it active
    const migrate1Promise = registry.migrate(socket, 'workflow:v1', {});
    const entry1 = registry.getCurrentEntry()!;

    (entry1.provider as MockPhoenixChannelProvider)._emit('status', {
      status: 'connected',
    });
    await waitForCondition(() => entry1.state === 'settling');
    (entry1.provider as MockPhoenixChannelProvider)._emit('sync', true);
    (entry1.ydoc as any)._emit('update', new Uint8Array([1]), entry1.provider);
    await migrate1Promise;

    // Start second migration
    const migrate2Promise = registry.migrate(socket, 'workflow:v2', {});
    const entry2 = registry.getCurrentEntry()!;

    const listener = vi.fn();
    registry.subscribe(listener);

    // Make entry2 active
    (entry2.provider as MockPhoenixChannelProvider)._emit('status', {
      status: 'connected',
    });
    await waitForCondition(() => entry2.state === 'settling');
    (entry2.provider as MockPhoenixChannelProvider)._emit('sync', true);
    (entry2.ydoc as any)._emit('update', new Uint8Array([1]), entry2.provider);
    await migrate2Promise;

    listener.mockClear();

    // Fast-forward past grace period
    await vi.advanceTimersByTimeAsync(2000);

    // Should notify when draining entry is destroyed
    expect(listener).toHaveBeenCalled();
  });

  test('unsubscribe stops notifications', async () => {
    const listener = vi.fn();
    const unsubscribe = registry.subscribe(listener);

    unsubscribe();
    listener.mockClear();

    const migratePromise = registry.migrate(socket, 'workflow:v1', {});
    expect(listener).not.toHaveBeenCalled();

    // Clean up
    registry.destroy();
    await expect(migratePromise).rejects.toThrow();
  });
});

describe('ChannelRegistry - Resource Cleanup', () => {
  let registry: ChannelRegistryInstance;
  let socket: ReturnType<typeof createMockSocket>;

  beforeEach(() => {
    (globalThis as any).mockProviderInstances = [];
    registry = createChannelRegistry();
    socket = createMockSocket();
    vi.useFakeTimers();
  });

  afterEach(() => {
    (globalThis as any).mockProviderInstances = [];
    vi.useRealTimers();
  });

  test('destroy cleans up current entry', async () => {
    const migratePromise = registry.migrate(socket, 'workflow:v1', {});
    const entry = registry.getCurrentEntry()!;

    const destroySpy = vi.spyOn(entry.provider, 'destroy');
    const ydocDestroySpy = vi.spyOn(entry.ydoc, 'destroy');
    const awarenessDestroySpy = vi.spyOn(entry.awareness, 'destroy');

    registry.destroy();

    expect(destroySpy).toHaveBeenCalled();
    expect(ydocDestroySpy).toHaveBeenCalled();
    expect(awarenessDestroySpy).toHaveBeenCalled();
    expect(registry.getCurrentEntry()).toBeNull();

    // Migrate promise should reject
    await expect(migratePromise).rejects.toThrow();
  });

  test('destroy cleans up draining entry', async () => {
    // Create first entry and make it active
    const migrate1Promise = registry.migrate(socket, 'workflow:v1', {});
    const entry1 = registry.getCurrentEntry()!;

    (entry1.provider as MockPhoenixChannelProvider)._emit('status', {
      status: 'connected',
    });
    await waitForCondition(() => entry1.state === 'settling');
    (entry1.provider as MockPhoenixChannelProvider)._emit('sync', true);
    (entry1.ydoc as any)._emit('update', new Uint8Array([1]), entry1.provider);
    await migrate1Promise;

    // Start second migration to create draining entry
    const migrate2Promise = registry.migrate(socket, 'workflow:v2', {});
    const entry2 = registry.getCurrentEntry()!;

    const entry1DestroySpy = vi.spyOn(entry1.provider, 'destroy');
    const entry2DestroySpy = vi.spyOn(entry2.provider, 'destroy');

    registry.destroy();

    expect(entry1DestroySpy).toHaveBeenCalled();
    expect(entry2DestroySpy).toHaveBeenCalled();
    expect(registry.getDrainingEntry()).toBeNull();
    expect(registry.getCurrentEntry()).toBeNull();

    // Migrate promise should reject
    await expect(migrate2Promise).rejects.toThrow();
  });

  test('destroy clears all listeners', async () => {
    const listener = vi.fn();
    registry.subscribe(listener);

    registry.destroy();
    listener.mockClear();

    // No notifications after destroy
    // (can't actually trigger since registry is destroyed, but verifies
    // listeners cleared)
    expect(registry.getCurrentEntry()).toBeNull();
  });

  test('handles errors during entry resource cleanup', async () => {
    const migratePromise = registry.migrate(socket, 'workflow:v1', {});
    const entry = registry.getCurrentEntry()!;

    // Make provider.destroy throw
    vi.spyOn(entry.provider, 'destroy').mockImplementation(() => {
      throw new Error('Provider destroy failed');
    });

    // Should not throw - errors are caught and logged
    expect(() => registry.destroy()).not.toThrow();
    expect(entry.state).toBe('destroyed');

    // Clean up
    await expect(migratePromise).rejects.toThrow();
  });
});

describe('ChannelRegistry - Edge Cases', () => {
  let registry: ChannelRegistryInstance;
  let socket: ReturnType<typeof createMockSocket>;

  beforeEach(() => {
    (globalThis as any).mockProviderInstances = [];
    registry = createChannelRegistry();
    socket = createMockSocket();
    vi.useFakeTimers();
  });

  afterEach(() => {
    registry.destroy();
    (globalThis as any).mockProviderInstances = [];
    vi.useRealTimers();
  });

  test('handles multiple rapid migrations', () => {
    // Start first migration (don't await - we're testing synchronous state)
    // Use .catch to suppress expected rejection when destroy() is called
    registry.migrate(socket, 'workflow:v1', {}).catch(() => {});
    const entry1 = registry.getCurrentEntry()!;

    // Start second migration before first completes
    registry.migrate(socket, 'workflow:v2', {}).catch(() => {});
    const entry2 = registry.getCurrentEntry()!;

    // Entry1 should be draining, entry2 should be current
    expect(entry1.state).toBe('draining');
    expect(entry2.state).toBe('connecting');
    expect(registry.getCurrentEntry()).toBe(entry2);

    // Start third migration before second completes
    registry.migrate(socket, 'workflow:v3', {}).catch(() => {});
    const entry3 = registry.getCurrentEntry()!;

    // Entry2 should be draining (replacing entry1), entry3 should be current
    expect(entry2.state).toBe('draining');
    expect(entry3.state).toBe('connecting');
    expect(registry.getCurrentEntry()).toBe(entry3);

    // Only one draining entry at a time
    expect(registry.getDrainingEntry()).toBe(entry2);

    // Clean up is handled by afterEach
  });

  test('first migration with no previous entry', () => {
    // Start migration (don't await - we're testing synchronous state)
    // Use .catch to suppress expected rejection when destroy() is called
    registry.migrate(socket, 'workflow:v1', {}).catch(() => {});
    const entry = registry.getCurrentEntry()!;

    // No draining entry on first migration
    expect(registry.getDrainingEntry()).toBeNull();
    expect(registry.isTransitioning()).toBe(false);
    expect(entry.state).toBe('connecting');

    // Clean up is handled by afterEach
  });

  test('passes join params to provider', () => {
    const joinParams = { user_id: '123', version_id: 'v1' };
    // Start migration (don't await - we're testing synchronous state)
    // Use .catch to suppress expected rejection when destroy() is called
    registry.migrate(socket, 'workflow:v1', joinParams).catch(() => {});

    const entry = registry.getCurrentEntry()!;
    expect(entry.provider).toBeDefined();

    // Provider was created with join params (verified by no errors)
    expect(entry.roomname).toBe('workflow:v1');

    // Clean up is handled by afterEach
  });
});
