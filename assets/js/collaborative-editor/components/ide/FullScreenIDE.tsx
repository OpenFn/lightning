import { useEffect, useRef } from "react";
import {
  Panel,
  PanelGroup,
  PanelResizeHandle,
  type ImperativePanelHandle,
} from "react-resizable-panels";

import { useURLState } from "../../../react/lib/use-url-state";
import { useSession } from "../../hooks/useSession";
import {
  useCurrentJob,
  useWorkflowActions,
} from "../../hooks/useWorkflow";
import { CollaborativeMonaco } from "../CollaborativeMonaco";

import { IDEHeader } from "./IDEHeader";

interface FullScreenIDEProps {
  jobId?: string;
  onClose: () => void;
}

/**
 * Full-Screen IDE component
 *
 * Provides a full-screen workspace for editing job code with:
 * - Header with job name and action buttons
 * - 3 resizable, collapsible panels (left, center, right)
 * - CollaborativeMonaco editor in center panel
 * - Placeholder content in left and right panels
 *
 * Panel layout persists to localStorage automatically.
 */
export function FullScreenIDE({ onClose }: FullScreenIDEProps) {
  const { searchParams } = useURLState();
  const jobIdFromURL = searchParams.get("job");
  const { selectJob } = useWorkflowActions();
  const { job: currentJob, ytext: currentJobYText } = useCurrentJob();
  const { awareness } = useSession();

  const leftPanelRef = useRef<ImperativePanelHandle>(null);
  const rightPanelRef = useRef<ImperativePanelHandle>(null);

  // Sync URL job ID to workflow store selection
  useEffect(() => {
    if (jobIdFromURL) {
      selectJob(jobIdFromURL);
    }
  }, [jobIdFromURL, selectJob]);

  // Debug: Log what we have
  console.log("[FullScreenIDE] Debug:", {
    jobIdFromURL,
    hasCurrentJob: !!currentJob,
    hasYText: !!currentJobYText,
    hasAwareness: !!awareness,
    currentJob,
    awareness,
  });

  // Loading state: Wait for Y.Text and awareness to be ready
  if (!currentJob || !currentJobYText || !awareness) {
    return (
      <div
        className="fixed inset-0 z-50 bg-white flex
          items-center justify-center"
      >
        <div className="text-center">
          <div
            className="hero-arrow-path size-8 animate-spin
            text-blue-500 mx-auto"
            aria-hidden="true"
          />
          <p className="text-gray-500 mt-2">Loading editor...</p>
        </div>
      </div>
    );
  }

  // Placeholder handlers for disabled buttons
  const handleSave = () => {
    console.log("Save clicked (not yet implemented)");
  };

  const handleRun = () => {
    console.log("Run clicked (not yet implemented)");
  };

  return (
    <div className="fixed inset-0 z-50 bg-white flex flex-col">
      {/* Header with Run, Save, Close buttons */}
      <IDEHeader
        jobName={currentJob.name}
        onClose={onClose}
        onSave={handleSave}
        onRun={handleRun}
      />

      {/* 3-panel layout */}
      <div className="flex-1 overflow-hidden">
        <PanelGroup
          direction="horizontal"
          autoSaveId="lightning.ide-layout"
          className="h-full"
        >
          {/* Left Panel - Placeholder for Input Picker / AI Assistant */}
          <Panel
            ref={leftPanelRef}
            defaultSize={0}
            minSize={15}
            maxSize={40}
            collapsible
            collapsedSize={0}
            className="bg-gray-50 border-r border-gray-200"
          >
            <div
              className="h-full p-4 flex items-center
              justify-center"
            >
              <div className="text-center text-gray-500">
                <p className="text-sm font-medium">
                  Input Picker / AI Assistant
                </p>
                <p className="text-xs mt-1">Coming Soon</p>
              </div>
            </div>
          </Panel>

          {/* Resize Handle */}
          <PanelResizeHandle
            className="w-1 bg-gray-200 hover:bg-blue-400
            transition-colors cursor-col-resize"
          />

          {/* Center Panel - CollaborativeMonaco Editor */}
          <Panel minSize={40} className="bg-white">
            <CollaborativeMonaco
              ytext={currentJobYText}
              awareness={awareness}
              adaptor={currentJob.adaptor || "common"}
              disabled={false}
              className="h-full w-full"
              options={{
                automaticLayout: true,
                minimap: { enabled: true },
                lineNumbers: "on",
                wordWrap: "on",
              }}
            />
          </Panel>

          {/* Resize Handle */}
          <PanelResizeHandle
            className="w-1 bg-gray-200 hover:bg-blue-400
            transition-colors cursor-col-resize"
          />

          {/* Right Panel - Placeholder for Run / Logs / Step I/O */}
          <Panel
            ref={rightPanelRef}
            defaultSize={0}
            minSize={20}
            maxSize={50}
            collapsible
            collapsedSize={0}
            className="bg-gray-50 border-l border-gray-200"
          >
            <div
              className="h-full p-4 flex items-center
              justify-center"
            >
              <div className="text-center text-gray-500">
                <p className="text-sm font-medium">
                  Run / Logs / Step I/O
                </p>
                <p className="text-xs mt-1">Coming Soon</p>
              </div>
            </div>
          </Panel>
        </PanelGroup>
      </div>
    </div>
  );
}
