/**
 * CollaborativeWorkflowDiagram - Wrapper for WorkflowDiagram using Yjs data
 * Phase 1: Basic rendering only - maps collaborative data to diagram format
 */

import { ReactFlowProvider } from "@xyflow/react";
import { useMemo, useRef, useState, useCallback, useEffect } from "react";

import {
  useHistory,
  useHistoryLoading,
  useHistoryError,
  useHistoryCommands,
  useHistoryChannelConnected,
} from "../../hooks/useHistory";
import { useIsNewWorkflow } from "../../hooks/useSessionContext";
import { useNodeSelection, useWorkflowState } from "../../hooks/useWorkflow";
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
  const workflow = useWorkflowState(state => state.workflow);
  const { currentNode, selectNode } = useNodeSelection();
  const isNewWorkflow = useIsNewWorkflow();
  const isHistoryChannelConnected = useHistoryChannelConnected();

  // Replace SAMPLE_HISTORY with HistoryStore data
  const history = useHistory();
  const historyLoading = useHistoryLoading();
  const historyError = useHistoryError();
  const { requestHistory, clearError } = useHistoryCommands();

  // Local state for history panel (persisted to localStorage)
  // Auto-expand if there's a run ID in the URL (like LiveView behavior)
  const [historyCollapsed, setHistoryCollapsed] = useState(() => {
    const params = new URLSearchParams(window.location.search);
    const hasRunIdInUrl = params.has("m");

    if (hasRunIdInUrl) {
      // If URL has a run ID, always expand the panel
      return false;
    }

    // Otherwise use localStorage preference
    const saved = localStorage.getItem("history-panel-collapsed");
    return saved === null ? true : saved === "true";
  });

  const handleToggleHistory = useCallback(() => {
    setHistoryCollapsed(prev => {
      const next = !prev;
      localStorage.setItem("history-panel-collapsed", String(next));
      return next;
    });
  }, []);

  // Track selected run for visual feedback (stored in URL)
  const [selectedRunId, setSelectedRunId] = useState<string | null>(() => {
    const params = new URLSearchParams(window.location.search);
    return params.get("m");
  });

  // Update URL when run selection changes
  const handleRunSelect = useCallback((run: Run) => {
    setSelectedRunId(run.id);

    const url = new URL(window.location.href);
    url.searchParams.set("m", run.id);
    window.history.pushState({}, "", url.toString());
  }, []);

  // Clear URL parameter when deselecting run
  const handleDeselectRun = useCallback(() => {
    setSelectedRunId(null);

    const url = new URL(window.location.href);
    url.searchParams.delete("m");
    window.history.pushState({}, "", url.toString());
  }, []);

  // Request history when panel is first expanded OR when there's a run ID in URL
  // Wait for channel to be connected before making request
  const hasRequestedHistory = useRef(false);
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const runIdFromUrl = params.get("m");

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

  // Don't render if no workflow data yet
  if (!workflow) {
    return (
      <div className={`flex items-center justify-center ${className}`}>
        <div className="text-center text-gray-500">
          <p>Loading workflow diagram...</p>
        </div>
      </div>
    );
  }

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
