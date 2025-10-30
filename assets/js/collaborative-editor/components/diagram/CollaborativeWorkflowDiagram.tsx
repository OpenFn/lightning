/**
 * CollaborativeWorkflowDiagram - Wrapper for WorkflowDiagram using Yjs data
 * Phase 1: Basic rendering only - maps collaborative data to diagram format
 */

import { ReactFlowProvider } from "@xyflow/react";
import { useMemo, useRef, useState, useCallback, useEffect } from "react";

import {
  useHistoryPanelCollapsed,
  useEditorPreferencesCommands,
} from "../../hooks/useEditorPreferences";
import {
  useHistory,
  useHistoryLoading,
  useHistoryError,
  useHistoryCommands,
  useHistoryChannelConnected,
} from "../../hooks/useHistory";
import { useIsNewWorkflow } from "../../hooks/useSessionContext";
import { useNodeSelection } from "../../hooks/useWorkflow";
import type { Run } from "../../types/history";

import MiniHistory from "./MiniHistory";
import CollaborativeWorkflowDiagramImpl from "./WorkflowDiagram";

interface CollaborativeWorkflowDiagramProps {
  className?: string;
  inspectorId?: string;
}

export function CollaborativeWorkflowDiagram({
  className = "h-full w-full",
  inspectorId,
}: CollaborativeWorkflowDiagramProps) {
  const { currentNode, selectNode } = useNodeSelection();
  const isNewWorkflow = useIsNewWorkflow();
  const isHistoryChannelConnected = useHistoryChannelConnected();

  // Replace SAMPLE_HISTORY with HistoryStore data
  const history = useHistory();
  const historyLoading = useHistoryLoading();
  const historyError = useHistoryError();
  const { requestHistory, clearError } = useHistoryCommands();

  // Use EditorPreferencesStore for history panel collapsed state
  const historyCollapsed = useHistoryPanelCollapsed();
  const { setHistoryPanelCollapsed } = useEditorPreferencesCommands();

  // Auto-expand if there's a run ID in the URL (like LiveView behavior)
  const runIdFromUrl = useMemo(() => {
    const params = new URLSearchParams(window.location.search);
    return params.get("run");
  }, []);

  useEffect(() => {
    if (runIdFromUrl && historyCollapsed) {
      setHistoryPanelCollapsed(false);
    }
  }, [runIdFromUrl, historyCollapsed, setHistoryPanelCollapsed]);

  const handleToggleHistory = useCallback(() => {
    setHistoryPanelCollapsed(!historyCollapsed);
  }, [historyCollapsed, setHistoryPanelCollapsed]);

  // Track selected run for visual feedback (stored in URL)
  const [selectedRunId, setSelectedRunId] = useState<string | null>(() => {
    const params = new URLSearchParams(window.location.search);
    return params.get("run");
  });

  // Update URL when run selection changes
  const handleRunSelect = useCallback((run: Run) => {
    setSelectedRunId(run.id);

    const url = new URL(window.location.href);
    url.searchParams.set("run", run.id);
    window.history.pushState({}, "", url.toString());
  }, []);

  // Clear URL parameter when deselecting run
  const handleDeselectRun = useCallback(() => {
    setSelectedRunId(null);

    const url = new URL(window.location.href);
    url.searchParams.delete("run");
    window.history.pushState({}, "", url.toString());
  }, []);

  // Request history when panel is first expanded OR when there's a run ID in URL
  // Wait for channel to be connected before making request
  const hasRequestedHistory = useRef(false);
  useEffect(() => {
    // Request if: channel connected AND (panel expanded OR run ID in URL) AND not already requested AND not new workflow
    const shouldRequest =
      isHistoryChannelConnected &&
      !hasRequestedHistory.current &&
      !isNewWorkflow &&
      (!historyCollapsed || runIdFromUrl);

    if (shouldRequest) {
      void requestHistory(runIdFromUrl || undefined);
      hasRequestedHistory.current = true;
    }
  }, [
    historyCollapsed,
    isNewWorkflow,
    isHistoryChannelConnected,
    requestHistory,
    runIdFromUrl,
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
        <CollaborativeWorkflowDiagramImpl
          selection={currentNode.id}
          onSelectionChange={selectNode}
          forceFit={true}
          showAiAssistant={false}
          inspectorId={inspectorId}
          containerEl={containerRef.current}
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
              clearError();
              void requestHistory();
            }}
          />
        )}
      </ReactFlowProvider>
    </div>
  );
}
