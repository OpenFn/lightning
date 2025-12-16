/**
 * useVersionMismatch - Detects when viewing latest workflow but selected run used older version
 *
 * Returns version mismatch info when:
 * - A run is selected
 * - Viewing "latest" workflow (not a specific snapshot)
 * - The run was executed on a different version than currently displayed
 *
 * This prevents confusion when the workflow structure has changed since the run executed.
 */

import { useMemo, useRef } from 'react';

import { useHistory } from './useHistory';
import { useLatestSnapshotLockVersion } from './useSessionContext';
import { useWorkflowState } from './useWorkflow';
import { useURLState } from '#/react/lib/use-url-state';

interface VersionMismatch {
  runVersion: number;
  currentVersion: number;
}

export function useVersionMismatch(
  selectedRunId: string | null
): VersionMismatch | null {
  const { params } = useURLState();
  const history = useHistory();
  const workflow = useWorkflowState(state => state.workflow);
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();
  const currVersion = params['v'] ? Number(params['v']) : null;

  // in the process of switching version
  const switching =
    currVersion !== null && currVersion !== workflow?.lock_version;

  return useMemo(() => {
    if (
      !selectedRunId ||
      !workflow ||
      !workflow.lock_version ||
      !latestSnapshotLockVersion
    ) {
      return null;
    }

    const workflowLockVersion = workflow.lock_version;

    // Find the work order that contains the selected run
    const selectedWorkOrder = history.find(wo =>
      wo.runs.some(run => run.id === selectedRunId)
    );

    if (!selectedWorkOrder || switching) return null;

    // Show warning when viewing a different version than the run used
    const runUsedDifferentVersion =
      selectedWorkOrder.version !== workflowLockVersion;

    if (runUsedDifferentVersion) {
      return {
        runVersion: selectedWorkOrder.version,
        currentVersion: workflowLockVersion,
      };
    }

    return null;
  }, [selectedRunId, workflow, latestSnapshotLockVersion, history]);
}
