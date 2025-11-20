/**
 * useJobMatchesRun Hook Tests
 *
 * Tests the useJobMatchesRun hook which determines if the currently
 * selected job has a corresponding step in the active run.
 *
 * Test Coverage:
 * - Returns true when no run is loaded
 * - Returns true when no job is selected
 * - Returns true when selected job has steps in the run
 * - Returns false when selected job has no steps in the run
 * - Handles multiple steps for the same job
 * - Reacts to run changes
 * - Reacts to job selection changes
 */

import { renderHook } from '@testing-library/react';
import type React from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { useJobMatchesRun } from '../../../js/collaborative-editor/hooks/useHistory';
import type {
  RunDetail,
  StepDetail,
} from '../../../js/collaborative-editor/types/history';

// Mock data factories
const createMockStep = (overrides?: Partial<StepDetail>): StepDetail => ({
  id: 'step-1',
  job_id: 'job-1',
  job: { name: 'Test Job' },
  exit_reason: null,
  error_type: null,
  started_at: null,
  finished_at: null,
  input_dataclip_id: null,
  output_dataclip_id: null,
  inserted_at: new Date().toISOString(),
  ...overrides,
});

const createMockRun = (steps: StepDetail[]): RunDetail => ({
  id: 'run-1',
  work_order_id: 'wo-1',
  work_order: {
    id: 'wo-1',
    workflow_id: 'wf-1',
  },
  state: 'started',
  created_by: null,
  starting_trigger: null,
  started_at: new Date().toISOString(),
  finished_at: null,
  steps,
});

/**
 * Creates a React wrapper with store providers for hook testing
 */
function createWrapper(
  activeRun: RunDetail | null = null
): React.ComponentType<{ children: React.ReactNode }> {
  // Track subscribers for testing reactivity
  const subscribers = new Set<() => void>();

  // Create mock history store
  const mockHistoryStore = {
    subscribe: vi.fn((listener: () => void) => {
      subscribers.add(listener);
      return () => subscribers.delete(listener);
    }),
    withSelector: vi.fn(selector => () => selector({ activeRun })),
    // Helper to trigger updates in tests
    _notifySubscribers: () => {
      subscribers.forEach(listener => listener());
    },
  };

  const mockStoreValue: StoreContextValue = {
    workflowStore: {} as any,
    sessionContextStore: {} as any,
    adaptorStore: {} as any,
    credentialStore: {} as any,
    awarenessStore: {} as any,
    historyStore: mockHistoryStore as any,
    uiStore: {} as any,
    editorPreferencesStore: {} as any,
  };

  return ({ children }: { children: React.ReactNode }) => (
    <StoreContext.Provider value={mockStoreValue}>
      {children}
    </StoreContext.Provider>
  );
}

describe('useJobMatchesRun', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('no run loaded', () => {
    test('returns true when no run is loaded and no job selected', () => {
      const wrapper = createWrapper(null);

      const { result } = renderHook(() => useJobMatchesRun(null), { wrapper });

      expect(result.current).toBe(true);
    });

    test('returns true when no run is loaded but job is selected', () => {
      const wrapper = createWrapper(null);

      const { result } = renderHook(() => useJobMatchesRun('job-1'), {
        wrapper,
      });

      expect(result.current).toBe(true);
    });
  });

  describe('run loaded, no job selected', () => {
    test('returns true when run is loaded but no job is selected', () => {
      const steps = [createMockStep({ job_id: 'job-1' })];
      const run = createMockRun(steps);
      const wrapper = createWrapper(run);

      const { result } = renderHook(() => useJobMatchesRun(null), { wrapper });

      expect(result.current).toBe(true);
    });
  });

  describe('job matches run', () => {
    test('returns true when selected job has a step in the run', () => {
      const steps = [createMockStep({ id: 'step-1', job_id: 'job-1' })];
      const run = createMockRun(steps);
      const wrapper = createWrapper(run);

      const { result } = renderHook(() => useJobMatchesRun('job-1'), {
        wrapper,
      });

      expect(result.current).toBe(true);
    });

    test('returns true when selected job has multiple steps in the run', () => {
      const steps = [
        createMockStep({ id: 'step-1', job_id: 'job-1' }),
        createMockStep({ id: 'step-2', job_id: 'job-1' }),
        createMockStep({ id: 'step-3', job_id: 'job-2' }),
      ];
      const run = createMockRun(steps);
      const wrapper = createWrapper(run);

      const { result } = renderHook(() => useJobMatchesRun('job-1'), {
        wrapper,
      });

      expect(result.current).toBe(true);
    });

    test('returns true when selected job is one of many in the run', () => {
      const steps = [
        createMockStep({ id: 'step-1', job_id: 'job-1' }),
        createMockStep({ id: 'step-2', job_id: 'job-2' }),
        createMockStep({ id: 'step-3', job_id: 'job-3' }),
      ];
      const run = createMockRun(steps);
      const wrapper = createWrapper(run);

      const { result } = renderHook(() => useJobMatchesRun('job-2'), {
        wrapper,
      });

      expect(result.current).toBe(true);
    });
  });

  describe('job does not match run', () => {
    test('returns false when selected job has no steps in the run', () => {
      const steps = [
        createMockStep({ id: 'step-1', job_id: 'job-1' }),
        createMockStep({ id: 'step-2', job_id: 'job-2' }),
      ];
      const run = createMockRun(steps);
      const wrapper = createWrapper(run);

      const { result } = renderHook(() => useJobMatchesRun('job-3'), {
        wrapper,
      });

      expect(result.current).toBe(false);
    });

    test('returns false when run has no steps at all', () => {
      const run = createMockRun([]);
      const wrapper = createWrapper(run);

      const { result } = renderHook(() => useJobMatchesRun('job-1'), {
        wrapper,
      });

      expect(result.current).toBe(false);
    });
  });

  describe('reactivity', () => {
    test('updates when job selection changes from matching to non-matching', () => {
      const steps = [createMockStep({ id: 'step-1', job_id: 'job-1' })];
      const run = createMockRun(steps);
      const wrapper = createWrapper(run);

      const { result, rerender } = renderHook(
        ({ jobId }) => useJobMatchesRun(jobId),
        {
          wrapper,
          initialProps: { jobId: 'job-1' },
        }
      );

      // Initially matches
      expect(result.current).toBe(true);

      // Change to non-matching job
      rerender({ jobId: 'job-2' });
      expect(result.current).toBe(false);
    });

    test('updates when job selection changes from non-matching to matching', () => {
      const steps = [createMockStep({ id: 'step-1', job_id: 'job-1' })];
      const run = createMockRun(steps);
      const wrapper = createWrapper(run);

      const { result, rerender } = renderHook(
        ({ jobId }) => useJobMatchesRun(jobId),
        {
          wrapper,
          initialProps: { jobId: 'job-2' },
        }
      );

      // Initially doesn't match
      expect(result.current).toBe(false);

      // Change to matching job
      rerender({ jobId: 'job-1' });
      expect(result.current).toBe(true);
    });

    test('updates when job selection is cleared', () => {
      const steps = [createMockStep({ id: 'step-1', job_id: 'job-1' })];
      const run = createMockRun(steps);
      const wrapper = createWrapper(run);

      const { result, rerender } = renderHook(
        ({ jobId }) => useJobMatchesRun(jobId),
        {
          wrapper,
          initialProps: { jobId: 'job-2' },
        }
      );

      // Initially doesn't match (job-2 not in run)
      expect(result.current).toBe(false);

      // Clear selection
      rerender({ jobId: null });
      expect(result.current).toBe(true);
    });
  });

  describe('edge cases', () => {
    test('handles steps with null job_id', () => {
      const steps = [
        createMockStep({ id: 'step-1', job_id: null }),
        createMockStep({ id: 'step-2', job_id: 'job-1' }),
      ];
      const run = createMockRun(steps);
      const wrapper = createWrapper(run);

      const { result } = renderHook(() => useJobMatchesRun('job-1'), {
        wrapper,
      });

      expect(result.current).toBe(true);
    });

    test('handles empty string job_id', () => {
      const steps = [createMockStep({ id: 'step-1', job_id: 'job-1' })];
      const run = createMockRun(steps);
      const wrapper = createWrapper(run);

      const { result } = renderHook(() => useJobMatchesRun(''), { wrapper });

      // Empty string is falsy, so it's treated like null (no job selected)
      // This should return true (no visual indication needed when no job selected)
      expect(result.current).toBe(true);
    });
  });
});
