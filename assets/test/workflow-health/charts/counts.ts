import type { RunStateCounts } from '#/workflow-health/useHealthStats';

/** Zero-filled run state counts, so a test only names the states it cares about. */
export const counts = (
  overrides: Partial<RunStateCounts> = {}
): RunStateCounts => ({
  success: 0,
  failed: 0,
  crashed: 0,
  cancelled: 0,
  killed: 0,
  exception: 0,
  lost: 0,
  ...overrides,
});
