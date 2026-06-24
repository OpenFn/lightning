/**
 * useProviderLifecycle Hook Tests
 *
 * Regression coverage for GitHub #4830: an in-place socket reconnect of an
 * already-saved "new" workflow must rejoin the channel with `action: "edit"`,
 * not the stale `action: "new"` frozen at mount.
 *
 * The hook reads join params lazily via `getJoinParams()` so the channel-join
 * `action` reflects the *current* saved state at both initial connect and
 * reconnect time.
 */

import { renderHook } from '@testing-library/react';
import type { Socket } from 'phoenix';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { useProviderLifecycle } from '../../../js/collaborative-editor/hooks/useProviderLifecycle';
import type { SessionStoreInstance } from '../../../js/collaborative-editor/stores/createSessionStore';
import { createMockSocket } from '../mocks/phoenixSocket';

// =============================================================================
// TEST HELPERS
// =============================================================================

/**
 * Minimal SessionStore stub exposing only the surface useProviderLifecycle
 * touches: a mutable `provider` reference and an `initializeSession` spy.
 */
function createSessionStoreStub() {
  const initializeSession = vi.fn(() => {
    // Mimic the real store: a provider exists after (re)initialisation.
    stub.provider = {
      id: Symbol('provider'),
    } as unknown as SessionStoreInstance['provider'];
  });

  const stub = {
    provider: null as SessionStoreInstance['provider'],
    initializeSession,
  } as unknown as SessionStoreInstance;

  return stub;
}

/** Extract the `joinParams` passed to the most recent initializeSession call. */
function lastJoinParams(store: SessionStoreInstance) {
  const calls = (store.initializeSession as ReturnType<typeof vi.fn>).mock
    .calls;
  const lastCall = calls[calls.length - 1];
  return lastCall?.[3]?.joinParams as { project_id: string; action: string };
}

// =============================================================================
// TESTS
// =============================================================================

describe('useProviderLifecycle join action freshness (#4830)', () => {
  let socket: Socket;

  beforeEach(() => {
    socket = createMockSocket() as unknown as Socket;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  test('initial join carries action "new" when the workflow is unsaved', () => {
    const sessionStore = createSessionStoreStub();
    let isNew = true;

    renderHook(() =>
      useProviderLifecycle({
        socket,
        isConnected: true,
        sessionStore,
        roomname: 'workflow:collaborate:wf-1',
        getJoinParams: () => ({
          project_id: 'proj-1',
          action: isNew ? 'new' : 'edit',
        }),
      })
    );

    expect(sessionStore.initializeSession).toHaveBeenCalledTimes(1);
    expect(lastJoinParams(sessionStore)).toEqual({
      project_id: 'proj-1',
      action: 'new',
    });
  });

  test('in-place reconnect rejoins with action "edit" after the workflow is saved', () => {
    const sessionStore = createSessionStoreStub();
    // `isNew` models the live SessionContextStore flag, flipped by
    // clearIsNewWorkflow() after the first successful save.
    let isNew = true;

    const { rerender } = renderHook(() =>
      useProviderLifecycle({
        socket,
        isConnected: true,
        sessionStore,
        roomname: 'workflow:collaborate:wf-1',
        getJoinParams: () => ({
          project_id: 'proj-1',
          action: isNew ? 'new' : 'edit',
        }),
      })
    );

    // First join used the seeded "new" action.
    expect(lastJoinParams(sessionStore)).toEqual({
      project_id: 'proj-1',
      action: 'new',
    });

    // Simulate: first save completes -> flag flips, then the provider is lost.
    isNew = false;
    sessionStore.provider = null;
    rerender();

    // Reconnect must have re-read the join params lazily and rejoined as "edit".
    expect(sessionStore.initializeSession).toHaveBeenCalledTimes(2);
    expect(lastJoinParams(sessionStore)).toEqual({
      project_id: 'proj-1',
      action: 'edit',
    });
  });
});
