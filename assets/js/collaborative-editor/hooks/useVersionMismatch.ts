/**
 * Detects that the selected run executed against content other than what is on
 * the canvas, so the shape being looked at is not the shape that ran.
 *
 * The run's results are painted onto the current document, and the banner says
 * so and offers to switch to the version the run used.
 *
 * There is nothing to warn about while a run is being read as it executed
 * (`?as_run=`), because then the document on screen is the one that ran. That
 * is the usual shape on a live workflow. It is not the shape in a draft, where
 * a run stays overlaid so the content can still be edited, and where this
 * banner is the whole explanation of the difference.
 */

import { useMemo } from 'react';

import { usePinnedView } from '../lib/pinnedView';

import { useHistory } from './useHistory';
import { useLatestSnapshotLockVersion } from './useSessionContext';
import { useWorkflowState } from './useWorkflow';

interface VersionMismatch {
  runVersion: number;
  currentVersion: number;
}

export function useVersionMismatch(
  selectedRunId: string | null
): VersionMismatch | null {
  const history = useHistory();
  const workflow = useWorkflowState(state => state.workflow);
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();

  const { snapshot, asRun } = usePinnedView();
  const currVersion = snapshot === null ? null : Number(snapshot);

  // in the process of switching version
  const switching =
    currVersion !== null && currVersion !== workflow?.lock_version;

  return useMemo(() => {
    if (
      asRun === selectedRunId ||
      !selectedRunId ||
      !workflow ||
      !workflow.lock_version ||
      !latestSnapshotLockVersion
    ) {
      return null;
    }

    const workflowLockVersion = workflow.lock_version;

    const selectedRun = history
      .flatMap(wo => wo.runs)
      .find(run => run.id === selectedRunId);

    if (!selectedRun || switching) return null;

    // Show warning when viewing a different version than the run used
    const runUsedDifferentVersion = selectedRun.version !== workflowLockVersion;

    if (runUsedDifferentVersion) {
      return {
        runVersion: selectedRun.version,
        currentVersion: workflowLockVersion,
      };
    }

    return null;
  }, [
    asRun,
    selectedRunId,
    switching,
    workflow,
    latestSnapshotLockVersion,
    history,
  ]);
}
