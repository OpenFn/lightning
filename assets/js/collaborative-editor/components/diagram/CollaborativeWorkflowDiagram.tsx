/**
 * CollaborativeWorkflowDiagram - Wrapper for WorkflowDiagram using Yjs data
 */

import { ReactFlowProvider } from '@xyflow/react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { cn } from '#/utils/cn';

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
import { useVersionSelect } from '../../hooks/useVersionSelect';
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

  // Get history data and commands
  const history = useHistory();
  const historyLoading = useHistoryLoading();
  const historyError = useHistoryError();
  const historyCommands = useHistoryCommands();

  // Use EditorPreferencesStore for history panel collapsed state
  const historyCollapsed = useHistoryPanelCollapsed();
  const { setHistoryPanelCollapsed } = useEditorPreferencesCommands();

  // Track selected run for visual feedback (stored in URL)
  const [selectedRunId, setSelectedRunId] = useState<string | null>(() => {
    const params = new URLSearchParams(window.location.search);
    return params.get('run');
  });

  // Auto-expand history panel when a run is selected
  useEffect(() => {
    if (selectedRunId && historyCollapsed) {
      setHistoryPanelCollapsed(false);
    }
  }, [selectedRunId, historyCollapsed, setHistoryPanelCollapsed]);

  const handleToggleHistory = useCallback(() => {
    setHistoryPanelCollapsed(!historyCollapsed);
  }, [historyCollapsed, setHistoryPanelCollapsed]);

  // Use hook to get run steps with automatic subscription management
  const currentRunSteps = useRunSteps(selectedRunId);

  // Detect version mismatch for warning banner
  const versionMismatch = useVersionMismatch(selectedRunId);

  // Get version selection handler
  const handleVersionSelect = useVersionSelect();

  // Update URL when run selection changes
  const handleRunSelect = useCallback(
    (run: RunSummary) => {
      setSelectedRunId(run.id);

      // Find the workorder that contains this run
      const workorder = history.find(wo => wo.runs.some(r => r.id === run.id));

      // Switch to the version this run was executed on
      if (workorder) {
        handleVersionSelect(workorder.version);
      }

      const url = new URL(window.location.href);
      url.searchParams.set('run', run.id);
      window.history.pushState({}, '', url.toString());
    },
    [history, handleVersionSelect]
  );

  // Clear URL parameter when deselecting run
  const handleDeselectRun = useCallback(() => {
    setSelectedRunId(null);

    const url = new URL(window.location.href);
    url.searchParams.delete('run');
    window.history.pushState({}, '', url.toString());
  }, []);

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
        {/* Version mismatch warning when viewing latest but run used older version */}
        {versionMismatch && (
          <VersionMismatchBanner
            runVersion={versionMismatch.runVersion}
            currentVersion={versionMismatch.currentVersion}
            className="absolute top-6 left-6 right-4 z-10 max-w-2xl mx-auto"
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
