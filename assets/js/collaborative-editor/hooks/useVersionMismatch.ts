/**
 * Detects that the selected run executed against content other than what is on
 * the canvas, so the shape being looked at is not the shape that ran.
 *
 * This is the answer for a user without experimental features: the run's results
 * are painted onto the current document, and the banner says so and offers to
 * switch to the version the run used. With the flag on there is nothing to
 * warn about, because selecting a run of older content opens that content
 * read-only (`?as_run=`) instead of painting it onto a document it never ran
 * against. So this returns null there rather than every caller remembering to
 * ask.
 */

import { useMemo } from 'react';

import { usePinnedView } from '../lib/pinnedView';

import { useHistory } from './useHistory';
import {
  useExperimentalFeatures,
  useLatestSnapshotLockVersion,
} from './useSessionContext';
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
  const experimentalFeatures = useExperimentalFeatures();

  // `?v=` numbers by the snapshot's own lock_version, which is what this
  // compares against. `?release=` numbers by the publish trail and is a
  // different question, which is why the two have different parameters.
  const { snapshot } = usePinnedView();
  const currVersion = snapshot === null ? null : Number(snapshot);

  // in the process of switching version
  const switching =
    currVersion !== null && currVersion !== workflow?.lock_version;

  return useMemo(() => {
    if (
      experimentalFeatures ||
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
    experimentalFeatures,
    selectedRunId,
    switching,
    workflow,
    latestSnapshotLockVersion,
    history,
  ]);
}
