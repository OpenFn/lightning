/**
 * CollaborativeWorkflowDiagram - Wrapper for WorkflowDiagram using Yjs data
 */

import { ReactFlowProvider } from '@xyflow/react';
import { useCallback, useEffect, useMemo, useRef } from 'react';

import { useURLState } from '#/react/lib/use-url-state';

import {
  useEditorPreferencesCommands,
  useHistoryPanelCollapsed,
} from '../../hooks/useEditorPreferences';
import {
  useFollowRun,
  useHistory,
  useHistoryChannelConnected,
  useHistoryCommands,
  useHistoryError,
  useHistoryLoading,
  useRunSteps,
  useRunSummary,
  useSelectedRunId,
} from '../../hooks/useHistory';
import {
  useIsNewWorkflow,
  useLatestSnapshotId,
  useExperimentalFeatures,
} from '../../hooks/useSessionContext';
import { useVersionMismatch } from '../../hooks/useVersionMismatch';
import { useVersionSelect } from '../../hooks/useVersionSelect';
import { useViewAsExecuted } from '../../hooks/useViewAsExecuted';
import { useNodeSelection } from '../../hooks/useWorkflow';
import { useKeyboardShortcut } from '../../keyboard';
import { CLEAR_PINNED_VIEW, usePinnedView } from '../../lib/pinnedView';
import type { RunSummary } from '../../types/history';
import { DiscardChangesDialog } from '../DiscardChangesDialog';

import MiniHistory from './MiniHistory';
import CollaborativeWorkflowDiagramImpl from './WorkflowDiagram';

interface CollaborativeWorkflowDiagramProps {
  className?: string;
  inspectorId?: string;
}

export function CollaborativeWorkflowDiagram({
  className = 'h-full w-full',
  inspectorId,
}: CollaborativeWorkflowDiagramProps) {
  const { currentNode, selectNode } = useNodeSelection();
  const isNewWorkflow = useIsNewWorkflow();
  const isHistoryChannelConnected = useHistoryChannelConnected();
  const { params, updateSearchParams } = useURLState();
  const latestSnapshotId = useLatestSnapshotId();

  const history = useHistory();
  const historyLoading = useHistoryLoading();
  const historyError = useHistoryError();
  const historyCommands = useHistoryCommands();

  const { viewAsExecuted, prompt: runPinPrompt } = useViewAsExecuted();

  // Switching to the version a run executed against destroys the document, so
  // it is guarded like every other switch. Offered by the mini history's
  // banner; owned here, because this is where the prompt can be rendered.
  const { handleVersionSelect, prompt: versionPrompt } = useVersionSelect();

  const historyCollapsed = useHistoryPanelCollapsed();
  const { setHistoryPanelCollapsed } = useEditorPreferencesCommands();

  // Falls back to the store's active run because LiveView push_patch strips
  // client-only URL params.
  const activeRunId = useSelectedRunId();
  const selectedRunId = params['run'] ?? activeRunId;

  const handleToggleHistory = useCallback(() => {
    setHistoryPanelCollapsed(!historyCollapsed);
  }, [historyCollapsed, setHistoryPanelCollapsed]);

  useKeyboardShortcut(
    'Control+h, Meta+h',
    () => {
      if (!isNewWorkflow) {
        handleToggleHistory();
      }
    },
    25, // Canvas priority (lower than IDE's 50)
    { enabled: !isNewWorkflow }
  );

  const runParam = params['run'] ?? null;
  const { release: releaseParam, asRun: asRunParam } = usePinnedView();

  // Opening a run on its own snapshot is the experimental experience. Without
  // the flag a run is only ever selected on the document already open, so none
  // of the view-switching below applies.
  const experimentalFeatures = useExperimentalFeatures();
  const restoredRunRef = useRef<string | null>(null);

  // Which document is on screen: a pinned release, a run's own snapshot, or the
  // live one. Leaving any of those for another is what has to drop the selected
  // run, and watching the release param alone missed the commonest way out of a
  // run view. Picking "latest" from a run view clears `as_run` while the release
  // param stays null, so nothing counted as a change, and the restore below put
  // the run straight back on the live document with its timings over steps it
  // never touched.
  const viewKey = `${releaseParam ?? ''}|${asRunParam ?? ''}`;
  const previousViewRef = useRef<string>(viewKey);

  // Does the run in the URL belong on the document in the URL? It does when
  // the view is that run's own, or when the run executed the content that is
  // live. Undefined snapshot means the history has not arrived, and nothing is
  // decided until it has.
  //
  // Without experimental features it always does, because there is no other
  // document to move it to: a run is selected where the user already is. That
  // makes the as-executed switch below inert, which is the whole gate.
  const urlRun = useRunSummary(runParam);
  const runBelongsHere =
    runParam !== null &&
    (!experimentalFeatures ||
      asRunParam === runParam ||
      (urlRun?.snapshot_id != null && urlRun.snapshot_id === latestSnapshotId));

  const { clearRun } = useFollowRun(selectedRunId);

  // Both jobs live in one effect so their order is deterministic: split apart,
  // the restore would race to re-add the run the switch is dropping. The ref
  // limits the restore to once per run to avoid a loop.
  useEffect(() => {
    const viewChanged = previousViewRef.current !== viewKey;

    if (viewChanged) {
      previousViewRef.current = viewKey;

      // Left one document for another and the run does not belong on the new
      // one, so it goes. A run that does belong stays: selecting a run of older
      // content moves to that run's own view, and a retry lands its new run on
      // the live document.
      if (!runBelongsHere) {
        restoredRunRef.current = null;
        if (activeRunId) {
          clearRun();
        }
        if (runParam) {
          updateSearchParams({ run: null, step: null });
        }
        return;
      }
    }

    // A run in the URL that executed something other than the live content is
    // shown as it executed, however the URL got that way: a click, a shared
    // link, a reload, the back button. Deciding this only on click left the old
    // behaviour reachable through the address bar.
    if (
      runParam &&
      !asRunParam &&
      urlRun?.snapshot_id != null &&
      !runBelongsHere
    ) {
      updateSearchParams({ as_run: runParam });
      return;
    }

    if (!runParam && activeRunId && restoredRunRef.current !== activeRunId) {
      restoredRunRef.current = activeRunId;
      updateSearchParams({ run: activeRunId });
    }
    if (runParam) {
      restoredRunRef.current = null;
    }
  }, [
    experimentalFeatures,
    viewKey,
    runParam,
    asRunParam,
    runBelongsHere,
    urlRun,
    activeRunId,
    clearRun,
    updateSearchParams,
  ]);

  const currentRunSteps = useRunSteps(selectedRunId);

  // Only ever set without experimental features. With the flag on, a run of
  // older content opens that content read-only, so the shape on screen is the
  // shape that ran and there is nothing to warn about.
  const versionMismatch = useVersionMismatch(selectedRunId);

  const handleGoToVersion = useCallback(() => {
    if (versionMismatch) {
      handleVersionSelect(versionMismatch.runVersion);
    }
  }, [handleVersionSelect, versionMismatch]);

  // A run is shown as it executed, on its own snapshot. The exception is a run
  // of the content that is live now: that one overlays on the live document so
  // the edit, run, edit loop keeps working.
  //
  // The comparison is against the live workflow, never against the document on
  // screen. A run view *is* a past document, so comparing against what is
  // displayed made the answer depend on where you happened to be standing, and
  // clicking two runs of the same content alternated between the two views.
  const handleRunSelect = useCallback(
    (run: RunSummary) => {
      // Opening a run on its own snapshot is part of the experimental
      // experience. Without the flag a run is selected on whatever document is
      // already open, as the editor did before, and the version-mismatch banner
      // is what says the shape on screen is not the shape that ran.
      if (!experimentalFeatures) {
        updateSearchParams({ run: run.id });
        return;
      }

      const ranTheLiveContent =
        latestSnapshotId !== null &&
        run.snapshot_id !== null &&
        run.snapshot_id !== undefined &&
        run.snapshot_id === latestSnapshotId;

      if (!ranTheLiveContent) {
        viewAsExecuted(run.id);
      } else {
        updateSearchParams({ ...CLEAR_PINNED_VIEW, run: run.id });
      }
    },
    [experimentalFeatures, latestSnapshotId, updateSearchParams, viewAsExecuted]
  );

  // Closes the run viewer in the store too, or the restore effect re-adds the
  // URL param immediately.
  const handleDeselectRun = useCallback(() => {
    clearRun();
    // The step belongs to the run. Left behind, it is re-applied to whichever
    // run is picked next, selecting a step from a different execution.
    updateSearchParams({ run: null, as_run: null, step: null });
  }, [clearRun, updateSearchParams]);

  // The run_id ensures that run's work order is included even if it is older
  // than the top 20.
  const hasRequestedHistory = useRef(false);
  useEffect(() => {
    const shouldRequest =
      isHistoryChannelConnected &&
      !hasRequestedHistory.current &&
      !isNewWorkflow &&
      (!historyCollapsed || selectedRunId);

    if (shouldRequest) {
      void historyCommands.requestHistory(
        selectedRunId || undefined,
        releaseParam || undefined
      );
      hasRequestedHistory.current = true;
    }
  }, [
    historyCollapsed,
    isNewWorkflow,
    isHistoryChannelConnected,
    historyCommands,
    selectedRunId,
    releaseParam,
  ]);

  // A pinned release is a different feed, so allow one more request.
  const lastReleaseParam = useRef(releaseParam);
  useEffect(() => {
    if (lastReleaseParam.current !== releaseParam) {
      lastReleaseParam.current = releaseParam;
      hasRequestedHistory.current = false;
    }
  }, [releaseParam]);

  // Find the selected run object in history
  const selectedRun = useMemo(() => {
    if (!selectedRunId) return null;

    // Search through work orders to find the run
    for (const workorder of history) {
      const run = workorder.runs.find(r => r.id === selectedRunId);
      if (run) return run;
    }
    return null;
  }, [selectedRunId, history]);

  // Transform history to mark selected run
  const historyWithSelection = useMemo(() => {
    if (!selectedRunId) return history;

    return history.map(workorder => ({
      ...workorder,
      runs: workorder.runs.map(run => ({
        ...run,
        selected: run.id === selectedRunId,
      })),
      selected: workorder.runs.some(run => run.id === selectedRunId),
    }));
  }, [selectedRunId, history]);

  // Create container ref for event delegation
  const containerRef = useRef<HTMLDivElement>(null);

  return (
    <div ref={containerRef} className={className}>
      <ReactFlowProvider>
        <CollaborativeWorkflowDiagramImpl
          selection={currentNode.id}
          onSelectionChange={selectNode}
          showAiAssistant={false}
          inspectorId={inspectorId}
          containerEl={containerRef.current!}
          runSteps={currentRunSteps}
        />

        {/* Only show history panel when NOT creating a new workflow */}
        {!isNewWorkflow && (
          <MiniHistory
            versionMismatch={versionMismatch}
            onGoToVersion={handleGoToVersion}
            collapsed={historyCollapsed}
            history={historyWithSelection}
            onCollapseHistory={handleToggleHistory}
            selectRunHandler={handleRunSelect}
            onDeselectRun={handleDeselectRun}
            selectedRun={selectedRun}
            loading={historyLoading}
            error={historyError}
            onRetry={() => {
              historyCommands.clearError();
              void historyCommands.requestHistory();
            }}
          />
        )}
      </ReactFlowProvider>
      <DiscardChangesDialog
        isOpen={versionPrompt.isAsking}
        onSaveAndContinue={versionPrompt.saveAndRunPending}
        onDiscardAndContinue={versionPrompt.runPending}
        onCancel={versionPrompt.cancel}
        description="Switching to the version this run executed against loads that version, and your unsaved changes cannot come with it. Switch without saving and they are gone."
      />
      <DiscardChangesDialog
        isOpen={runPinPrompt.isAsking}
        onSaveAndContinue={runPinPrompt.saveAndRunPending}
        onDiscardAndContinue={runPinPrompt.runPending}
        onCancel={runPinPrompt.cancel}
        description="Opening this run loads the version it executed against, and your unsaved changes cannot come with it. Switch without saving and they are gone."
      />
    </div>
  );
}
