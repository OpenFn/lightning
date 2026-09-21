
import { renderHook } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import type React from 'react';

import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { useCanRun } from '../../../js/collaborative-editor/hooks/useWorkflow';

let experimentalFeatures = true;
let isPinnedView = true;
let isNewWorkflow = false;

vi.mock('../../../js/collaborative-editor/hooks/useSession', () => ({
  useSession: () => ({ isSynced: true }),
}));

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useExperimentalFeatures: () => experimentalFeatures,
  useIsNewWorkflow: () => isNewWorkflow,
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

let workflowState: {
  jobs: unknown[];
  triggers: unknown[];
  workflow: null;
} = { jobs: [], triggers: [], workflow: null };

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
    isNewWorkflow = false;
    workflowState = { jobs: [], triggers: [], workflow: null };
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

  describe('useCanRun on an unsaved new workflow', () => {
    beforeEach(() => {
      experimentalFeatures = true;
      isPinnedView = false;
      isNewWorkflow = true;
      workflowState = { jobs: [{}], triggers: [], workflow: null };
    });

    test('refuses the run and says to create it first', () => {
      const { result } = renderHook(() => useCanRun(), { wrapper });

      expect(result.current.canRun).toBe(false);
      expect(result.current.tooltipMessage).toBe(
        'Create this workflow before running it'
      );
    });

    test('refuses it without experimental features too', () => {
      // The base refused this through the read-only lock, which useCanRun no
      // longer consults. Gating the replacement on the flag would let a
      // flag-off user run a workflow that does not exist yet.
      experimentalFeatures = false;

      const { result } = renderHook(() => useCanRun(), { wrapper });

      expect(result.current.canRun).toBe(false);
      expect(result.current.tooltipMessage).toBe(
        'Create this workflow before running it'
      );
    });
  });
});
