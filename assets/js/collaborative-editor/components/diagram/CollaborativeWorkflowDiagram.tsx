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
  useHistory,
  useHistoryChannelConnected,
  useHistoryCommands,
  useHistoryError,
  useHistoryLoading,
  useRunSteps,
} from '../../hooks/useHistory';
import { useIsNewWorkflow } from '../../hooks/useSessionContext';
import { useVersionMismatch } from '../../hooks/useVersionMismatch';
import { useNodeSelection } from '../../hooks/useWorkflow';
import type { RunSummary } from '../../types/history';

import MiniHistory from './MiniHistory';
import { VersionMismatchBanner } from './VersionMismatchBanner';
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

  // Get history data and commands
  const history = useHistory();
  const historyLoading = useHistoryLoading();
  const historyError = useHistoryError();
  const historyCommands = useHistoryCommands();

  // Use EditorPreferencesStore for history panel collapsed state
  const historyCollapsed = useHistoryPanelCollapsed();
  const { setHistoryPanelCollapsed } = useEditorPreferencesCommands();

  // Read selected run ID from URL - single source of truth
  // useURLState is reactive, so component re-renders when URL changes
  const selectedRunId = params['run'] ?? null;

  const handleToggleHistory = useCallback(() => {
    setHistoryPanelCollapsed(!historyCollapsed);
  }, [historyCollapsed, setHistoryPanelCollapsed]);

  // Use hook to get run steps with automatic subscription management
  const currentRunSteps = useRunSteps(selectedRunId);

  // Detect version mismatch for warning banner
  const versionMismatch = useVersionMismatch(selectedRunId);

  // Update URL when run selection changes
  // URLStore notifies subscribers synchronously, triggering immediate re-render
  const handleRunSelect = useCallback(
    (run: RunSummary) => {
      // Find the workorder that contains this run
      const workorder = history.find(wo => wo.runs.some(r => r.id === run.id));

      // Single atomic update - both version and run in one call
      // This prevents race conditions between two separate updateSearchParams calls
      updateSearchParams({
        v: workorder ? String(workorder.version) : null,
        run: run.id,
      });
    },
    [history, updateSearchParams]
  );

  // Clear URL parameter when deselecting run
  const handleDeselectRun = useCallback(() => {
    updateSearchParams({ run: null });
  }, [updateSearchParams]);

  // Request history when panel is first expanded OR when there's a run ID selected
  // Wait for channel to be connected before making request
  const hasRequestedHistory = useRef(false);
  useEffect(() => {
    // Request if: channel connected AND (panel expanded OR run ID selected) AND not already requested AND not new workflow
    const shouldRequest =
      isHistoryChannelConnected &&
      !hasRequestedHistory.current &&
      !isNewWorkflow &&
      (!historyCollapsed || selectedRunId);

    if (shouldRequest) {
      void historyCommands.requestHistory(selectedRunId || undefined);
      hasRequestedHistory.current = true;
    }
  }, [
    historyCollapsed,
    isNewWorkflow,
    isHistoryChannelConnected,
    historyCommands,
    selectedRunId,
  ]);

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
        {versionMismatch && (
          <VersionMismatchBanner
            runVersion={versionMismatch.runVersion}
            currentVersion={versionMismatch.currentVersion}
            className="absolute top-4 left-1/2 -translate-x-1/2 z-50 max-w-md"
          />
        )}

        <CollaborativeWorkflowDiagramImpl
          selection={currentNode.id}
          onSelectionChange={selectNode}
          forceFit={true}
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
