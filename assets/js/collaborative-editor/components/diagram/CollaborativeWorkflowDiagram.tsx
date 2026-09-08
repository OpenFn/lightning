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
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();
  const workflow = useWorkflowState(state => state.workflow);

  const history = useHistory();
  const historyLoading = useHistoryLoading();
  const historyError = useHistoryError();
  const historyCommands = useHistoryCommands();

  const { viewAsExecuted, prompt: runPinPrompt } = useViewAsExecuted();

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
  const versionParam = params['v'] ?? null;
  const restoredRunRef = useRef<string | null>(null);
  const previousVersionRef = useRef<string | null>(versionParam);
  // A `?v` change means two different things: a dropdown switch, which must
  // clear the selected run, or selecting a run of another version, which must
  // not. Set on run-select, consumed by the reconcile effect below.
  const runSelectInProgressRef = useRef(false);

  const { clearRun } = useFollowRun(selectedRunId);

  // Both jobs live in one effect so their order is deterministic: split apart,
  // the restore would race to re-add the run the switch is dropping. The ref
  // limits the restore to once per run to avoid a loop.
  useEffect(() => {
    const versionChanged = previousVersionRef.current !== versionParam;
    const wasRunSelect = runSelectInProgressRef.current;
    runSelectInProgressRef.current = false;

    if (versionChanged) {
      previousVersionRef.current = versionParam;
      if (!wasRunSelect) {
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

  const currentRunSteps = useRunSteps(selectedRunId);

  // A run of the current version overlays on the live document; a run of any
  // other version loads that run's own snapshot, which covers draft runs that
  // no release can address.
  const handleRunSelect = useCallback(
    (run: RunSummary) => {
      const currentLockVersion =
        workflow?.lock_version ?? latestSnapshotLockVersion ?? null;
      const isDifferentVersion =
        run.version !== null &&
        run.version !== undefined &&
        currentLockVersion !== null &&
        run.version !== currentLockVersion;

      // Set only where the URL is actually about to change. Pinning a run can
      // be blocked by the unsaved-changes prompt, and a flag left standing
      // would make the next version change skip clearing the run.
      if (isDifferentVersion) {
        viewAsExecuted(run.id, () => {
          runSelectInProgressRef.current = true;
        });
      } else {
        runSelectInProgressRef.current = true;
        updateSearchParams({ v: null, as_run: null, run: run.id });
      }
    },
    [workflow, latestSnapshotLockVersion, updateSearchParams, viewAsExecuted]
  );

  // Closes the run viewer in the store too, or the restore effect re-adds the
  // URL param immediately.
  const handleDeselectRun = useCallback(() => {
    clearRun();
    updateSearchParams({ run: null, as_run: null });
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

  // A pinned version is a different feed, so allow one more request.
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
