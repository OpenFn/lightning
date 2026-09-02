import type { WorkOrderStateCounts } from '#/workflow-health/types';

/**
 * Zero-filled work order state counts, so a test only names the states it cares
 * about.
 */
export const counts = (
  overrides: Partial<WorkOrderStateCounts> = {}
): WorkOrderStateCounts => ({
  success: 0,
  failed: 0,
  crashed: 0,
  cancelled: 0,
  killed: 0,
  exception: 0,
  lost: 0,
  rejected: 0,
  ...overrides,
});
