/**
 * SessionProvider <-> StoreProvider join-action bridge integration test (#4830)
 *
 * Regression coverage for the *full* client-side bridge that keeps the
 * channel-join `action` honest across an in-place reconnect:
 *
 *   clearIsNewWorkflow() on the SessionContextStore
 *     -> StoreProvider effect subscribes & forwards via setIsNewWorkflow
 *       -> SessionProvider ref write (isNewWorkflowRef.current = false)
 *         -> getJoinParams() re-read lazily on the NEXT (re)connect
 *           -> PhoenixChannelProvider constructed with params.action === "edit"
 *
 * Unlike `useProviderLifecycle.test.tsx` (which hand-rolls `getJoinParams`),
 * this test renders the REAL provider wiring — `SessionProvider` wrapping
 * `StoreProvider`, exactly how `CollaborativeEditor.tsx` composes them — so the
 * bridge effect, the ref, and the lazy getter are all exercised together.
 *
 * The transport boundary is captured by faking the `y-phoenix-channel`
 * `PhoenixChannelProvider` constructor: every (re)connect records the `params`
 * (i.e. the join params) it was constructed with. We assert on `params.action`.
 *
 * Pre-fix proof: against the frozen-prop implementation (where the join params
 * were captured once at mount instead of read lazily), the reconnect would
 * reconstruct the provider with the stale `action: "new"` and the second
 * assertion below would fail. See the inline NOTE on the reconnect assertion.
 */

import { act, render } from '@testing-library/react';
import type React from 'react';
import { useState } from 'react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

// ---------------------------------------------------------------------------
// Transport-boundary fake: y-phoenix-channel PhoenixChannelProvider
// ---------------------------------------------------------------------------
//
// The real SessionStore constructs `new PhoenixChannelProvider(socket, room,
// ydoc, { params, ... })`. We replace that class with a minimal event-emitter
// fake exposing only the surface SessionStore touches (on/off/emit, synced,
// doc, awareness, channel, destroy) and record the params of every
// construction so the test can assert what was sent on connect vs reconnect.

const providerConstructions: { params: Record<string, unknown> }[] = [];

vi.mock('y-phoenix-channel', () => {
  class FakePhoenixChannelProvider {
    public synced = false;
    public doc: unknown;
    public awareness: unknown;
    public channel: { on: () => void; off: () => void; push: () => void };
    private handlers = new Map<string, Set<(...args: unknown[]) => void>>();

    constructor(
      _socket: unknown,
      _roomname: string,
      ydoc: unknown,
      options: { awareness?: unknown; params?: Record<string, unknown> } = {}
    ) {
      this.doc = ydoc;
      this.awareness = options.awareness ?? { destroy: () => {} };
      this.channel = { on: () => {}, off: () => {}, push: () => {} };
      providerConstructions.push({ params: options.params ?? {} });
    }

    on(event: string, handler: (...args: unknown[]) => void) {
      if (!this.handlers.has(event)) this.handlers.set(event, new Set());
      this.handlers.get(event)!.add(handler);
    }

    off(event: string, handler: (...args: unknown[]) => void) {
      this.handlers.get(event)?.delete(handler);
    }

    emit(event: string, args: unknown[]) {
      this.handlers.get(event)?.forEach(h => h(...args));
    }

    destroy() {
      this.handlers.clear();
    }
  }

  return {
    PhoenixChannelProvider: FakePhoenixChannelProvider,
    messageAwareness: 1,
    messageQueryAwareness: 3,
    messageSync: 0,
  };
});

// ---------------------------------------------------------------------------
// Capture the REAL store instances created inside the provider tree so the
// test can (a) flip isNewWorkflow via the real clearIsNewWorkflow() and
// (b) null the session provider to drive an in-place reconnect.
// ---------------------------------------------------------------------------

const capturedSessionStores: SessionStoreInstance[] = [];
const capturedSessionContextStores: SessionContextStoreInstance[] = [];

vi.mock(
  '../../../js/collaborative-editor/stores/createSessionStore',
  async importOriginal => {
    const mod =
      await importOriginal<
        typeof import('../../../js/collaborative-editor/stores/createSessionStore')
      >();
    return {
      ...mod,
      createSessionStore: () => {
        const store = mod.createSessionStore();
        capturedSessionStores.push(store);
        return store;
      },
    };
  }
);

vi.mock(
  '../../../js/collaborative-editor/stores/createSessionContextStore',
  async importOriginal => {
    const mod =
      await importOriginal<
        typeof import('../../../js/collaborative-editor/stores/createSessionContextStore')
      >();
    return {
      ...mod,
      createSessionContextStore: (isNewWorkflow?: boolean) => {
        const store = mod.createSessionContextStore(isNewWorkflow);
        capturedSessionContextStores.push(store);
        return store;
      },
    };
  }
);

// Imports AFTER vi.mock so the mocked modules are used.
import { SessionProvider } from '../../../js/collaborative-editor/contexts/SessionProvider';
import { StoreProvider } from '../../../js/collaborative-editor/contexts/StoreProvider';
import type { SessionContextStoreInstance } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import type { SessionStoreInstance } from '../../../js/collaborative-editor/stores/createSessionStore';
import { SocketContext } from '../../../js/react/contexts/SocketProvider';
import { createMockSocket } from '../mocks/phoenixSocket';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Wraps children in a connected SocketContext using the existing mock socket.
 * We feed the SocketContext directly (rather than the real SocketProvider,
 * which would build a real PhoenixSocket) so `socket` is non-null and
 * `isConnected` is true — the precondition useProviderLifecycle needs to
 * (re)create the provider.
 */
/**
 * Connected socket provider that keeps `isConnected: true` throughout but
 * exposes a `forceRerender` so the test can trigger a fresh render of the
 * provider tree (e.g. after dropping the live channel) without mutating any
 * useProviderLifecycle dependency. This lets the reconnect effect observe the
 * provider transition to null and rebuild it.
 */
let forceRerender: () => void = () => {};

function ConnectedSocket({
  socket,
  children,
}: {
  socket: unknown;
  children: React.ReactNode;
}) {
  const [, setTick] = useState(0);
  // eslint-disable-next-line react-compiler/react-compiler -- test harness: expose a render trigger to the enclosing test
  forceRerender = () => setTick(t => t + 1);
  return (
    <SocketContext.Provider
      value={{
        socket: socket as never,
        isConnected: true,
        connectionError: null,
        connect: () => {},
        disconnect: () => {},
      }}
    >
      {children}
    </SocketContext.Provider>
  );
}

/** action carried by the params of the Nth provider construction (0-based). */
function actionOfConstruction(index: number): unknown {
  return providerConstructions[index]?.params['action'];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('SessionProvider/StoreProvider join-action bridge (#4830)', () => {
  beforeEach(() => {
    providerConstructions.length = 0;
    capturedSessionStores.length = 0;
    capturedSessionContextStores.length = 0;
  });

  afterEach(() => {
    capturedSessionStores.forEach(store => {
      try {
        store.destroy();
      } catch {
        /* already destroyed */
      }
    });
    vi.clearAllMocks();
  });

  test('initial connect joins with action "new", then a reconnect after clearIsNewWorkflow() rejoins with action "edit"', () => {
    const socket = createMockSocket();

    const tree = (
      <ConnectedSocket socket={socket}>
        <SessionProvider
          workflowId="wf-1"
          projectId="proj-1"
          isNewWorkflow={true}
        >
          <StoreProvider>
            <div data-testid="child" />
          </StoreProvider>
        </SessionProvider>
      </ConnectedSocket>
    );

    act(() => {
      render(tree);
    });

    // --- Assertion 1: initial connect carries action "new" -----------------
    expect(providerConstructions.length).toBeGreaterThanOrEqual(1);
    expect(actionOfConstruction(0)).toBe('new');
    const constructionsAfterInitial = providerConstructions.length;

    // The real bridge must have wired the SessionContextStore -> ref.
    expect(capturedSessionStores.length).toBe(1);
    expect(capturedSessionContextStores.length).toBe(1);

    const sessionStore = capturedSessionStores[0];
    const sessionContextStore = capturedSessionContextStores[0];

    // Sanity: the seeded store flag reflects the prop.
    expect(sessionContextStore.getSnapshot().isNewWorkflow).toBe(true);

    // Settle the live provider so SessionProvider commits a render that
    // observes a non-null provider. useProviderLifecycle's reconnect effect
    // then records that provider as its "previous" reference — the baseline a
    // subsequent provider-loss is compared against.
    act(() => {
      sessionStore.provider?.emit('sync', [true]);
    });

    // --- Drive the REAL path: first save completes -> flag cleared ---------
    // This is exactly what useWorkflow.tsx (~436) calls after a successful
    // save of a new workflow. The StoreProvider bridge effect is subscribed,
    // so this propagates synchronously into SessionProvider's `isNewWorkflow`
    // ref (no re-render needed for a ref write).
    act(() => {
      sessionContextStore.clearIsNewWorkflow();
    });
    expect(sessionContextStore.getSnapshot().isNewWorkflow).toBe(false);

    // --- Simulate provider loss + in-place reconnect -----------------------
    // Drop the live provider (mirrors a lost channel) and force a re-render
    // while still connected. useProviderLifecycle's reconnect effect detects
    // the had-provider -> null transition and rebuilds the provider, re-reading
    // getJoinParams() lazily.
    act(() => {
      sessionStore.destroy();
      forceRerender();
    });

    // --- Assertion 2: reconnect carries action "edit" ----------------------
    // NOTE (pre-fix proof): with the old frozen-prop code, getJoinParams was
    // captured once at mount holding action: "new", so this reconnect would
    // reconstruct the provider with "new" and this assertion would FAIL.
    expect(providerConstructions.length).toBeGreaterThan(
      constructionsAfterInitial
    );
    const lastIndex = providerConstructions.length - 1;
    expect(actionOfConstruction(lastIndex)).toBe('edit');
  });
});
