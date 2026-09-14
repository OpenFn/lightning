/**
 * useCanRun — what stops a run, and what does not.
 *
 * The interesting case is a version being read. A fresh run has no content to
 * run there and stays refused; a retry carries the version its own run
 * executed, so it goes ahead. That exemption is part of the sandboxes work, so
 * it waits for the experimental flag: without it, a pinned view refuses every
 * run exactly as it does on main.
 */

import { renderHook } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import type React from 'react';

import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { useCanRun } from '../../../js/collaborative-editor/hooks/useWorkflow';

let experimentalFeatures = true;
let isPinnedView = true;

vi.mock('../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({ isSynced: true }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useExperimentalFeatures: () => experimentalFeatures,
  useIsNewWorkflow: () => false,
  useLimits: () => ({}),
  usePermissions: () => ({
    can_edit_workflow: true,
    can_run_workflow: true,
  }),
  useContentLocked: () => false,
  useLatestSnapshotLockVersion: () => 1,
  useUser: () => null,
  useWorkflowTemplate: () => null,
}));

vi.mock('../../../js/collaborative-editor/lib/pinnedView', () => ({
  usePinnedView: () => ({ isPinnedView }),
}));

// The workflow store supplies only the jobs and triggers behind the
// unsaved-new-workflow check, which is not what these tests are about.
const workflowState = { jobs: [], triggers: [], workflow: null };

const stores = {
  workflowStore: {
    subscribe: () => () => {},
    withSelector: (selector: (state: typeof workflowState) => unknown) => () =>
      selector(workflowState),
  },
} as unknown as StoreContextValue;

const wrapper = ({ children }: { children: React.ReactNode }) => (
  <StoreContext.Provider value={stores}>{children}</StoreContext.Provider>
);

describe('useCanRun on a version being read', () => {
  beforeEach(() => {
    experimentalFeatures = true;
    isPinnedView = true;
  });

  test('refuses a fresh run, and says why', () => {
    const { result } = renderHook(() => useCanRun(), { wrapper });

    expect(result.current.canRun).toBe(false);
    expect(result.current.tooltipMessage).toBe(
      'You are viewing a pinned version of this workflow'
    );
  });

  test('lets a retry through', () => {
    const { result } = renderHook(() => useCanRun({ forRetry: true }), {
      wrapper,
    });

    expect(result.current.canRun).toBe(true);
  });

  test('refuses a retry too without experimental features', () => {
    // Main refuses every run on a pinned view. A user who did not opt in must
    // not find a control they have never had.
    experimentalFeatures = false;

    const { result } = renderHook(() => useCanRun({ forRetry: true }), {
      wrapper,
    });

    expect(result.current.canRun).toBe(false);
    expect(result.current.tooltipMessage).toBe(
      'You are viewing a pinned version of this workflow'
    );
  });

  test('allows both when nothing is pinned', () => {
    isPinnedView = false;

    const { result } = renderHook(
      () => ({
        fresh: useCanRun(),
        retry: useCanRun({ forRetry: true }),
      }),
      { wrapper }
    );

    expect(result.current.fresh.canRun).toBe(true);
    expect(result.current.retry.canRun).toBe(true);
  });
});
