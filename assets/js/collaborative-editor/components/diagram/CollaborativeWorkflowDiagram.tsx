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
  useSelectedRunId,
} from '../../hooks/useHistory';
import {
  useIsNewWorkflow,
  useLatestSnapshotLockVersion,
} from '../../hooks/useSessionContext';
import { useViewAsExecuted } from '../../hooks/useViewAsExecuted';
import { useNodeSelection, useWorkflowState } from '../../hooks/useWorkflow';
import { useKeyboardShortcut } from '../../keyboard';
import type { RunSummary } from '../../types/history';

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
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();
  const workflow = useWorkflowState(state => state.workflow);

  // Get history data and commands
  const history = useHistory();
  const historyLoading = useHistoryLoading();
  const historyError = useHistoryError();
  const historyCommands = useHistoryCommands();

  // Load a run's model read-only exactly as it executed (?as_run → :run: room).
  const viewAsExecuted = useViewAsExecuted();

  // Use EditorPreferencesStore for history panel collapsed state
  const historyCollapsed = useHistoryPanelCollapsed();
  const { setHistoryPanelCollapsed } = useEditorPreferencesCommands();

  // Read selected run ID from URL, falling back to the history store's active run.
  // The fallback prevents losing the run when LiveView push_patch strips
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
  const versionParam = params['v'] ?? null;
  const restoredRunRef = useRef<string | null>(null);
  const previousVersionRef = useRef<string | null>(versionParam);
  // Distinguishes the two sources of a `?v` change: an explicit dropdown version
  // switch (which must clear the selected run) vs. selecting a run of a
  // different version (which sets/clears `?v` as part of loading that run and
  // must NOT clear it). handleRunSelect sets this; the reconcile effect consumes
  // it on the next run.
  const runSelectInProgressRef = useRef(false);

  // Follow the run to receive real-time step updates via run:${runId} channel
  // This is essential for highlighting steps as they execute in real-time
  const { clearRun } = useFollowRun(selectedRunId);

  // Reconcile the selected run with the URL and the current version.
  //
  // Two jobs, in one effect so their ordering is deterministic (a separate
  // earlier effect would race to re-add a run we are trying to drop):
  //
  // 1. Dropdown version switch: the previously selected run belongs to the OLD
  //    version, so it must not survive. Clear it from the history store (which
  //    stops the canvas step overlay, since `selectedRunId` falls back to the
  //    store's activeRun) and from the URL. This is scoped to an *explicit*
  //    version switch: a run-select that changes `?v` (as-executed) sets
  //    runSelectInProgressRef so we do NOT clear the run it is selecting.
  // 2. Otherwise, restore `?run` if LiveView push_patch stripped it while the
  //    store still has an active run. The ref limits this to one restore per
  //    activeRunId to avoid loops.
  useEffect(() => {
    const versionChanged = previousVersionRef.current !== versionParam;
    // Consume the run-select marker once (covers both the version-changing and
    // non-version-changing run selections, so it never goes stale).
    const wasRunSelect = runSelectInProgressRef.current;
    runSelectInProgressRef.current = false;

    if (versionChanged) {
      previousVersionRef.current = versionParam;
      if (!wasRunSelect) {
        // Explicit dropdown switch → drop the previously selected run.
        restoredRunRef.current = null;
        if (activeRunId) {
          clearRun();
        }
        if (runParam) {
          updateSearchParams({ run: null });
        }
        return;
      }
    }

    if (!runParam && activeRunId && restoredRunRef.current !== activeRunId) {
      restoredRunRef.current = activeRunId;
      updateSearchParams({ run: activeRunId });
    }
    if (runParam) {
      restoredRunRef.current = null;
    }
  }, [versionParam, runParam, activeRunId, clearRun, updateSearchParams]);

  // Use hook to get run steps with automatic subscription management
  const currentRunSteps = useRunSteps(selectedRunId);

  // Render the selected run faithfully:
  // - Same version as the current canvas → overlay its step highlighting on the
  //   live/current document (also covers watching an in-progress run).
  // - A different version → load that run's model read-only, exactly as it
  //   executed, via the `?as_run` → `:run:<id>` room (works for draft runs too).
  //
  // Either way this is a run-select, NOT a dropdown version switch, so mark it
  // so the reconcile effect does not clear the run it is selecting.
  const handleRunSelect = useCallback(
    (run: RunSummary) => {
      runSelectInProgressRef.current = true;

      const currentLockVersion =
        workflow?.lock_version ?? latestSnapshotLockVersion ?? null;
      const isDifferentVersion =
        run.version !== null &&
        run.version !== undefined &&
        currentLockVersion !== null &&
        run.version !== currentLockVersion;

      if (isDifferentVersion) {
        // Sets ?as_run=<id> (+ run for step highlighting), clears any ?v= pin.
        viewAsExecuted(run.id);
      } else {
        // Overlay on the current document; clear any as-executed / pin view.
        updateSearchParams({ v: null, as_run: null, run: run.id });
      }
    },
    [workflow, latestSnapshotLockVersion, updateSearchParams, viewAsExecuted]
  );

  // Clear the run selection on deselect, including any as-executed view, so we
  // return to the current editable canvas.
  // Also close the run viewer in the history store so the restore effect
  // (which watches activeRunId) does not immediately re-add the URL param.
  const handleDeselectRun = useCallback(() => {
    clearRun();
    updateSearchParams({ run: null, as_run: null });
  }, [clearRun, updateSearchParams]);

  // Request history when the panel is first expanded OR when there's a run ID
  // selected. Pinning a version scopes the feed to that version's runs, so the
  // one-shot guard resets when the pinned version changes. Wait for the channel to be connected. The
  // one-shot ref avoids duplicate requests; the run_id ensures that run's work
  // order is included even if it's older than the top 20.
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
        versionParam || undefined
      );
      hasRequestedHistory.current = true;
    }
  }, [
    historyCollapsed,
    isNewWorkflow,
    isHistoryChannelConnected,
    historyCommands,
    selectedRunId,
    versionParam,
  ]);

  // A different pinned version is a different feed, so allow one more request.
  const lastVersionParam = useRef(versionParam);
  useEffect(() => {
    if (lastVersionParam.current !== versionParam) {
      lastVersionParam.current = versionParam;
      hasRequestedHistory.current = false;
    }
  }, [versionParam]);

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
    </div>
  );
}
