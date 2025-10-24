/**
 * CollaborativeWorkflowDiagram - Wrapper for WorkflowDiagram using Yjs data
 * Phase 1: Basic rendering only - maps collaborative data to diagram format
 */

import { ReactFlowProvider } from "@xyflow/react";
import { useMemo, useRef, useState } from "react";

import { useIsNewWorkflow } from "../../hooks/useSessionContext";
import { useNodeSelection, useWorkflowState } from "../../hooks/useWorkflow";
import type { WorkflowRunHistory } from "../../types/history";

import MiniHistory from "./MiniHistory";
import CollaborativeWorkflowDiagramImpl from "./WorkflowDiagram";

interface CollaborativeWorkflowDiagramProps {
  className?: string;
  inspectorId?: string;
}

// Phase 1: Hardcoded sample data (most recent 10 work orders)
// TODO Phase 2: Replace with real data from backend
const SAMPLE_HISTORY: WorkflowRunHistory[] = [
  {
    id: "e2107d46-cf29-4930-b11b-cbcfcf83549d",
    version: 29,
    state: "success",
    runs: [
      {
        id: "7d5e0711-e2fd-44a4-91cc-fa0c335f88e4",
        state: "success",
        started_at: "2025-10-23T21:00:01.106711Z",
        error_type: null,
        finished_at: "2025-10-23T21:00:02.098356Z",
        selected: false,
      },
    ],
    last_activity: "2025-10-23T21:00:02.293382Z",
    selected: false,
  },
  {
    id: "547d11ad-cf57-434f-b0d1-2b511b9557dc",
    version: 29,
    state: "success",
    runs: [
      {
        id: "14ee8074-9f6a-4b8a-b44d-138e96702087",
        state: "success",
        started_at: "2025-10-23T20:45:01.709297Z",
        error_type: null,
        finished_at: "2025-10-23T20:45:02.505881Z",
        selected: false,
      },
    ],
    last_activity: "2025-10-23T20:45:02.712046Z",
    selected: false,
  },
  {
    id: "6443ba23-79e8-4779-b1bd-25158bd66cbe",
    version: 29,
    state: "success",
    runs: [
      {
        id: "f37c0de9-c4fb-49e6-af78-27b95ce03240",
        state: "success",
        started_at: "2025-10-23T20:30:01.070370Z",
        error_type: null,
        finished_at: "2025-10-23T20:30:01.900177Z",
        selected: false,
      },
    ],
    last_activity: "2025-10-23T20:30:02.064561Z",
    selected: false,
  },
  {
    id: "b65107f9-2a5f-4bd1-b97d-b8500a58f621",
    version: 29,
    state: "success",
    runs: [
      {
        id: "8c7087f8-7f9e-48d9-a074-dc58b5fd9fb9",
        state: "success",
        started_at: "2025-10-23T20:15:01.791928Z",
        error_type: null,
        finished_at: "2025-10-23T20:15:02.619074Z",
        selected: false,
      },
    ],
    last_activity: "2025-10-23T20:15:02.825683Z",
    selected: false,
  },
  {
    id: "b18b25b7-0b4a-4467-bdb2-d5676595de86",
    version: 29,
    state: "success",
    runs: [
      {
        id: "e76ce911-d215-4dfa-ab09-fba0959ed8ba",
        state: "success",
        started_at: "2025-10-23T20:00:01.400483Z",
        error_type: null,
        finished_at: "2025-10-23T20:00:02.282543Z",
        selected: false,
      },
    ],
    last_activity: "2025-10-23T20:00:02.462210Z",
    selected: false,
  },
  {
    id: "7f0419b6-e35b-4b7c-8ddd-f1fbfa84cf2c",
    version: 29,
    state: "success",
    runs: [
      {
        id: "d1f87a82-1052-4a51-b279-a6205adfa2e7",
        state: "success",
        started_at: "2025-10-23T19:45:01.960858Z",
        error_type: null,
        finished_at: "2025-10-23T19:45:02.955735Z",
        selected: false,
      },
    ],
    last_activity: "2025-10-23T19:45:03.123050Z",
    selected: false,
  },
  {
    id: "8c5f37f8-5c86-4af7-b165-a92aa21974a1",
    version: 29,
    state: "success",
    runs: [
      {
        id: "caaba485-c216-42de-b3d7-8b510380910b",
        state: "success",
        started_at: "2025-10-23T19:30:00.977340Z",
        error_type: null,
        finished_at: "2025-10-23T19:30:01.800263Z",
        selected: false,
      },
    ],
    last_activity: "2025-10-23T19:30:01.981189Z",
    selected: false,
  },
  {
    id: "ac7eb46c-f353-43e5-94b3-f4dde9b8c14b",
    version: 29,
    state: "success",
    runs: [
      {
        id: "8ef27ee6-aa89-435f-847e-1817f791d14e",
        state: "success",
        started_at: "2025-10-23T19:15:01.585779Z",
        error_type: null,
        finished_at: "2025-10-23T19:15:02.488919Z",
        selected: false,
      },
    ],
    last_activity: "2025-10-23T19:15:02.672166Z",
    selected: false,
  },
  {
    id: "99d11684-e9f4-4ec8-b1a0-c157266f8950",
    version: 29,
    state: "success",
    runs: [
      {
        id: "1051b941-a637-43be-b575-5a949eae41d1",
        state: "success",
        started_at: "2025-10-23T18:45:01.214588Z",
        error_type: null,
        finished_at: "2025-10-23T18:45:02.078961Z",
        selected: false,
      },
    ],
    last_activity: "2025-10-23T18:45:02.269822Z",
    selected: false,
  },
  {
    id: "3e376d05-2d07-44d9-8a40-76f7f2f1382b",
    version: 29,
    state: "success",
    runs: [
      {
        id: "0e249e9b-2d11-4fa2-aa4f-e1628607a486",
        state: "success",
        started_at: "2025-10-23T18:30:01.755262Z",
        error_type: null,
        finished_at: "2025-10-23T18:30:02.589317Z",
        selected: false,
      },
    ],
    last_activity: "2025-10-23T18:30:02.770334Z",
    selected: false,
  },
];

export function CollaborativeWorkflowDiagram({
  className = "h-full w-full",
  inspectorId,
}: CollaborativeWorkflowDiagramProps) {
  const workflow = useWorkflowState(state => state.workflow);
  const { currentNode, selectNode } = useNodeSelection();
  const isNewWorkflow = useIsNewWorkflow();

  // Local state for history panel collapse/expand
  const [historyCollapsed, setHistoryCollapsed] = useState(true);

  // Track selected run for visual feedback (Phase 1 - local state only)
  // Phase 2 will integrate with diagram state
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);

  // Transform history to mark selected run
  const historyWithSelection = useMemo(() => {
    if (!selectedRunId) return SAMPLE_HISTORY;

    return SAMPLE_HISTORY.map(workorder => ({
      ...workorder,
      runs: workorder.runs.map(run => ({
        ...run,
        selected: run.id === selectedRunId,
      })),
      selected: workorder.runs.some(run => run.id === selectedRunId),
    }));
  }, [selectedRunId]);

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
            onCollapseHistory={() => {
              // Clear selection first (clicking selected run should deselect)
              setSelectedRunId(null);
              // Then toggle collapse state
              setHistoryCollapsed(!historyCollapsed);
            }}
            selectRunHandler={run => {
              // Phase 1: Local visual selection only
              // Phase 2: Will integrate with diagram to show run state
              setSelectedRunId(run.id);
              console.log("Run selected:", run.id);
            }}
          />
        )}
      </ReactFlowProvider>
    </div>
  );
}
