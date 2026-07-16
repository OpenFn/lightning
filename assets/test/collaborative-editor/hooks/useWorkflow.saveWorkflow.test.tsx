/**
 * useWorkflowActions().saveWorkflow — contract + notify behaviour
 *
 * Covers the shared save wrapper in `useWorkflow.tsx`
 * (`handleSaveSuccess`/`handleSaveError`/`wrappedSaveWorkflow`): the
 * `{ notify }` toast gating, the persistent Retry toast for brand-new
 * workflows, and the retry loop. `store.saveWorkflow` itself (the Y.Doc /
 * channel plumbing) is out of scope here — it's covered by
 * `createWorkflowStore.test.ts`; this file only exercises the wrapper.
 */

import { renderHook, waitFor } from '@testing-library/react';
import type React from 'react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { LiveViewActionsProvider } from '../../../js/collaborative-editor/contexts/LiveViewActionsContext';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { useWorkflowActions } from '../../../js/collaborative-editor/hooks/useWorkflow';
import { notifications } from '../../../js/collaborative-editor/lib/notifications';
import { createSessionContextStore } from '../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionContext } from '../__helpers__/sessionContextFactory';
import { simulateStoreProviderWithConnection } from '../__helpers__/storeProviderHelpers';
import { createMinimalWorkflowYDoc } from '../__helpers__/workflowStoreHelpers';

vi.mock('../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: {
    alert: vi.fn(),
    info: vi.fn(),
    success: vi.fn(),
    dismiss: vi.fn(),
  },
}));

// window.liveSocket is undefined in jsdom; useWorkflow.tsx's URL-patch code
// path is exercised via `navigate` (LiveViewActionsProvider) rather than
// liveSocket directly, so no stub is needed for that. Stubbed here anyway in
// case any code path checks it, to avoid a silent no-op.
const mockNavigate = vi.fn();

async function createTestSetup(isNewWorkflow: boolean) {
  const ydoc = createMinimalWorkflowYDoc('workflow-1', 'Test Workflow', 1);

  const { stores, sessionStore, cleanup } =
    await simulateStoreProviderWithConnection(
      'test:room',
      { id: 'user-1', name: 'Test User', color: '#ff0000' },
      { workflowYDoc: ydoc }
    );

  // `simulateStoreProviderWithConnection` always builds sessionContextStore
  // via the no-arg `createStores()`, which hardcodes `isNewWorkflow: false`
  // at construction (there's no public setter — only `clearIsNewWorkflow`).
  // Replace it with one seeded correctly, then connect + seed it the same
  // way StoreProvider does on mount so `project`/`permissions` are populated.
  const sessionContextStore = createSessionContextStore(isNewWorkflow);
  const provider = sessionStore.getProvider();
  if (!provider) throw new Error('Expected a connected provider in test setup');
  sessionContextStore._connectChannel(provider);
  const mockChannel = provider.channel as unknown as {
    _test: { emit: (event: string, payload: unknown) => void };
  };
  mockChannel._test.emit('session_context', createSessionContext());

  const testStores = { ...stores, sessionContextStore };

  const saveWorkflowSpy = vi.spyOn(testStores.workflowStore, 'saveWorkflow');

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <LiveViewActionsProvider
      actions={{
        pushEvent: vi.fn(),
        pushEventTo: vi.fn(),
        handleEvent: vi.fn(() => vi.fn()),
        navigate: mockNavigate,
      }}
    >
      <StoreContext.Provider value={testStores}>
        {children}
      </StoreContext.Provider>
    </LiveViewActionsProvider>
  );

  const { result } = renderHook(() => useWorkflowActions(), { wrapper });

  return {
    result,
    saveWorkflowSpy,
    sessionContextStore,
    cleanup: () => {
      cleanup();
    },
  };
}

describe('useWorkflowActions().saveWorkflow', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('success', () => {
    test('resolves with the store response', async () => {
      const { result, saveWorkflowSpy, cleanup } = await createTestSetup(false);
      saveWorkflowSpy.mockResolvedValue({
        saved_at: '2024-01-01T00:00:00Z',
        lock_version: 2,
      });

      const response = await result.current.saveWorkflow();

      expect(response).toEqual({
        saved_at: '2024-01-01T00:00:00Z',
        lock_version: 2,
      });
      cleanup();
    });

    test('shows the success toast when notify is "all" (default)', async () => {
      const { result, saveWorkflowSpy, cleanup } = await createTestSetup(false);
      saveWorkflowSpy.mockResolvedValue({
        saved_at: '2024-01-01T00:00:00Z',
        lock_version: 2,
      });

      await result.current.saveWorkflow();

      expect(notifications.info).toHaveBeenCalledWith(
        expect.objectContaining({ title: 'Workflow saved' })
      );
      cleanup();
    });

    test('shows no toast when notify is "error-only" or "none"', async () => {
      const { result, saveWorkflowSpy, cleanup } = await createTestSetup(false);
      saveWorkflowSpy.mockResolvedValue({
        saved_at: '2024-01-01T00:00:00Z',
        lock_version: 2,
      });

      await result.current.saveWorkflow({ notify: 'error-only' });
      await result.current.saveWorkflow({ notify: 'none' });

      expect(notifications.info).not.toHaveBeenCalled();
      cleanup();
    });
  });

  describe('failure', () => {
    test('notify "error-only": shows an alert with a Retry action and rethrows', async () => {
      const { result, saveWorkflowSpy, cleanup } = await createTestSetup(false);
      saveWorkflowSpy.mockRejectedValue(new Error('network error'));

      await expect(
        result.current.saveWorkflow({ notify: 'error-only' })
      ).rejects.toThrow('network error');

      expect(notifications.alert).toHaveBeenCalledWith(
        expect.objectContaining({
          title: 'Failed to save workflow',
          action: expect.objectContaining({ label: 'Retry' }) as object,
        })
      );
      cleanup();
    });

    test('notify "none": shows no toast but still rethrows', async () => {
      const { result, saveWorkflowSpy, cleanup } = await createTestSetup(false);
      saveWorkflowSpy.mockRejectedValue(new Error('network error'));

      await expect(
        result.current.saveWorkflow({ notify: 'none' })
      ).rejects.toThrow('network error');

      expect(notifications.alert).not.toHaveBeenCalled();
      cleanup();
    });
  });

  describe('persistent Retry toast for new workflows', () => {
    test('isNewWorkflow true: Retry alert has duration: Infinity', async () => {
      const { result, saveWorkflowSpy, cleanup } = await createTestSetup(true);
      saveWorkflowSpy.mockRejectedValue(new Error('network error'));

      await expect(
        result.current.saveWorkflow({ notify: 'error-only' })
      ).rejects.toThrow();

      expect(notifications.alert).toHaveBeenCalledWith(
        expect.objectContaining({ duration: Infinity })
      );
      cleanup();
    });

    test('isNewWorkflow false: no duration override', async () => {
      const { result, saveWorkflowSpy, cleanup } = await createTestSetup(false);
      saveWorkflowSpy.mockRejectedValue(new Error('network error'));

      await expect(
        result.current.saveWorkflow({ notify: 'error-only' })
      ).rejects.toThrow();

      const call = vi.mocked(notifications.alert).mock.calls[0]?.[0] as {
        duration?: number;
      };
      expect(call.duration).toBeUndefined();
      cleanup();
    });
  });

  describe('retry loop', () => {
    test('a failing retry re-issues a Retry alert with no unhandled rejection; a successful retry shows the saved toast and runs isNewWorkflow handling', async () => {
      const { result, saveWorkflowSpy, sessionContextStore, cleanup } =
        await createTestSetup(true);
      saveWorkflowSpy.mockRejectedValue(new Error('network error'));

      await expect(
        result.current.saveWorkflow({ notify: 'error-only' })
      ).rejects.toThrow();

      const firstCall = vi.mocked(notifications.alert).mock
        .calls[0]?.[0] as unknown as {
        action: { onClick: () => void };
      };
      expect(firstCall.action).toBeDefined();

      // Retry while still failing: a second Retry alert, no unhandled
      // rejection (onClick's `.catch(() => {})` swallows it).
      firstCall.action.onClick();
      await waitFor(() => {
        expect(vi.mocked(notifications.alert).mock.calls.length).toBe(2);
      });
      const secondCall = vi.mocked(notifications.alert).mock.calls[1]?.[0] as {
        title: string;
        duration?: number;
      };
      expect(secondCall.title).toBe('Failed to save workflow');
      expect(secondCall.duration).toBe(Infinity);

      // Now make the retry succeed.
      saveWorkflowSpy.mockResolvedValue({
        saved_at: '2024-01-01T00:00:00Z',
        lock_version: 3,
      });
      const clearIsNewWorkflowSpy = vi.spyOn(
        sessionContextStore,
        'clearIsNewWorkflow'
      );

      const secondCallForRetry = vi.mocked(notifications.alert).mock
        .calls[1]?.[0] as unknown as { action: { onClick: () => void } };
      secondCallForRetry.action.onClick();

      await waitFor(() => {
        expect(notifications.info).toHaveBeenCalledWith(
          expect.objectContaining({ title: 'Workflow saved' })
        );
      });
      // Retry calls wrappedSaveWorkflow() with no options -> notify: 'all',
      // which is what surfaces the success toast for a retry that recovers.
      expect(clearIsNewWorkflowSpy).toHaveBeenCalled();
      cleanup();
    });
  });
});
