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
  useContentLocked,
  useIsNewWorkflow,
  useLatestSnapshotId,
  useLatestSnapshotLockVersion,
  useExperimentalFeatures,
} from '../../hooks/useSessionContext';
import { useVersionMismatch } from '../../hooks/useVersionMismatch';
import { useVersionSelect } from '../../hooks/useVersionSelect';
import { useViewAsExecuted } from '../../hooks/useViewAsExecuted';
import { useNodeSelection } from '../../hooks/useWorkflow';
import { useKeyboardShortcut } from '../../keyboard';
import {
  CLEAR_PINNED_VIEW,
  SNAPSHOT_PARAM,
  usePinnedView,
} from '../../lib/pinnedView';
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
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();

  const history = useHistory();
  const historyLoading = useHistoryLoading();
  const historyError = useHistoryError();
  const historyCommands = useHistoryCommands();

  const { viewAsExecuted, prompt: runPinPrompt } = useViewAsExecuted();

  const { handleVersionSelect, prompt: versionPrompt } = useVersionSelect();

  const historyCollapsed = useHistoryPanelCollapsed();
  const { setHistoryPanelCollapsed } = useEditorPreferencesCommands();

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
  const contentLocked = useContentLocked();
  const { release: releaseParam, asRun: asRunParam } = usePinnedView();

  const experimentalFeatures = useExperimentalFeatures();
  const restoredRunRef = useRef<string | null>(null);

  const viewKey = `${releaseParam ?? ''}|${asRunParam ?? ''}`;
  const previousViewRef = useRef<string>(viewKey);
  const previousRunRef = useRef<string | null>(runParam);

  const urlRun = useRunSummary(runParam);
  const runBelongsHere =
    runParam !== null &&
    (!experimentalFeatures ||
      !contentLocked ||
      asRunParam === runParam ||
      (urlRun?.snapshot_id != null && urlRun.snapshot_id === latestSnapshotId));

  const { clearRun } = useFollowRun(selectedRunId);

  useEffect(() => {
    const viewChanged = previousViewRef.current !== viewKey;

    const runChanged = previousRunRef.current !== runParam;
    previousRunRef.current = runParam;

    if (viewChanged) {
      previousViewRef.current = viewKey;

      if (runChanged && runParam) return;

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

    if (
      runParam &&
      !asRunParam &&
      contentLocked &&
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
    contentLocked,
    urlRun,
    latestSnapshotId,
    activeRunId,
    clearRun,
    updateSearchParams,
  ]);

  const currentRunSteps = useRunSteps(selectedRunId);

  const versionMismatch = useVersionMismatch(selectedRunId);

  const handleGoToVersion = useCallback(() => {
    if (!versionMismatch) return;

    if (contentLocked && selectedRunId) {
      viewAsExecuted(selectedRunId);
      return;
    }

    handleVersionSelect(versionMismatch.runVersion);
  }, [
    contentLocked,
    handleVersionSelect,
    selectedRunId,
    versionMismatch,
    viewAsExecuted,
  ]);

  const handleRunSelect = useCallback(
    (run: RunSummary) => {
      if (!experimentalFeatures) {
        const ranAnotherVersion =
          run.version !== null &&
          run.version !== undefined &&
          run.version !== latestSnapshotLockVersion;

        updateSearchParams({
          [SNAPSHOT_PARAM]: ranAnotherVersion ? String(run.version) : null,
          run: run.id,
        });
        return;
      }

      const ranTheLiveContent =
        latestSnapshotId !== null &&
        run.snapshot_id !== null &&
        run.snapshot_id !== undefined &&
        run.snapshot_id === latestSnapshotId;

      if (!ranTheLiveContent && contentLocked) {
        viewAsExecuted(run.id);
      } else {
        updateSearchParams({ ...CLEAR_PINNED_VIEW, run: run.id });
      }
    },
    [
      contentLocked,
      experimentalFeatures,
      latestSnapshotId,
      latestSnapshotLockVersion,
      updateSearchParams,
      viewAsExecuted,
    ]
  );

  const handleDeselectRun = useCallback(() => {
    clearRun();
    updateSearchParams({ run: null, as_run: null, step: null });
  }, [clearRun, updateSearchParams]);

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
