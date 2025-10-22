import { useEffect, useRef, useState } from "react";
import {
  Panel,
  PanelGroup,
  PanelResizeHandle,
  type ImperativePanelHandle,
} from "react-resizable-panels";

import { useURLState } from "../../../react/lib/use-url-state";
import { useSession } from "../../hooks/useSession";
import {
  useCanSave,
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
  const { selectJob, saveWorkflow } = useWorkflowActions();
  const { job: currentJob, ytext: currentJobYText } = useCurrentJob();
  const { awareness } = useSession();
  const { canSave, tooltipMessage } = useCanSave();

  const leftPanelRef = useRef<ImperativePanelHandle>(null);
  const centerPanelRef = useRef<ImperativePanelHandle>(null);
  const rightPanelRef = useRef<ImperativePanelHandle>(null);

  const [isLeftCollapsed, setIsLeftCollapsed] = useState(true);
  const [isCenterCollapsed, setIsCenterCollapsed] = useState(false);
  const [isRightCollapsed, setIsRightCollapsed] = useState(true);

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

  // Check how many panels are open
  const openPanelCount =
    (!isLeftCollapsed ? 1 : 0) +
    (!isCenterCollapsed ? 1 : 0) +
    (!isRightCollapsed ? 1 : 0);

  // Toggle handlers for panel collapse/expand
  const toggleLeftPanel = () => {
    if (!isLeftCollapsed && openPanelCount === 1) return;
    if (isLeftCollapsed) {
      leftPanelRef.current?.expand();
    } else {
      leftPanelRef.current?.collapse();
    }
  };

  const toggleCenterPanel = () => {
    if (!isCenterCollapsed && openPanelCount === 1) return;
    if (isCenterCollapsed) {
      centerPanelRef.current?.expand();
    } else {
      centerPanelRef.current?.collapse();
    }
  };

  const toggleRightPanel = () => {
    if (!isRightCollapsed && openPanelCount === 1) return;
    if (isRightCollapsed) {
      rightPanelRef.current?.expand();
    } else {
      rightPanelRef.current?.collapse();
    }
  };

  // Handler for Save button
  const handleSave = () => {
    void saveWorkflow();
  };

  // Placeholder handler for disabled Run button
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
        canSave={canSave}
        saveTooltip={tooltipMessage}
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
            defaultSize={1}
            minSize={5}
            collapsible
            collapsedSize={1}
            onCollapse={() => setIsLeftCollapsed(true)}
            onExpand={() => setIsLeftCollapsed(false)}
            className="bg-gray-50 border-r border-gray-200"
          >
            <div className="h-full flex flex-col">
              {/* Panel heading */}
              <div
                className={`shrink-0 transition-transform ${
                  isLeftCollapsed ? "rotate-90" : ""
                }`}
              >
                <div className="flex items-center justify-between px-3 py-2">
                  <button
                    onClick={toggleLeftPanel}
                    className="text-xs font-medium text-gray-400
                      uppercase tracking-wide hover:text-gray-600
                      transition-colors cursor-pointer"
                  >
                    Input
                  </button>
                  {!isLeftCollapsed && (
                    <button
                      onClick={toggleLeftPanel}
                      disabled={openPanelCount === 1}
                      className="text-gray-400 hover:text-gray-600
                        disabled:opacity-30 disabled:cursor-not-allowed
                        transition-colors"
                      aria-label="Collapse left panel"
                    >
                      <span
                        className="hero-chevron-left size-3"
                        aria-hidden="true"
                      />
                    </button>
                  )}
                </div>
              </div>

              {/* Panel content */}
              {!isLeftCollapsed && (
                <div className="flex-1 p-4 flex items-center
                  justify-center">
                  <div className="text-center text-gray-500">
                    <p className="text-sm font-medium">
                      Input Picker / AI Assistant
                    </p>
                    <p className="text-xs mt-1">Coming Soon</p>
                  </div>
                </div>
              )}
            </div>
          </Panel>

          {/* Resize Handle */}
          <PanelResizeHandle
            className="w-1 bg-gray-200 hover:bg-blue-400
            transition-colors cursor-col-resize"
          />

          {/* Center Panel - CollaborativeMonaco Editor */}
          <Panel
            ref={centerPanelRef}
            defaultSize={100}
            minSize={15}
            collapsible
            collapsedSize={1}
            onCollapse={() => setIsCenterCollapsed(true)}
            onExpand={() => setIsCenterCollapsed(false)}
            className="bg-white"
          >
            <div className="h-full flex flex-col">
              {/* Panel heading */}
              <div
                className={`shrink-0 border-b border-gray-100 transition-transform ${
                  isCenterCollapsed ? "rotate-90" : ""
                }`}
              >
                <div className="flex items-center justify-between px-3 py-2">
                  <button
                    onClick={toggleCenterPanel}
                    className="text-xs font-medium text-gray-400
                      uppercase tracking-wide hover:text-gray-600
                      transition-colors cursor-pointer"
                  >
                    Code
                  </button>
                  {!isCenterCollapsed && (
                    <button
                      onClick={toggleCenterPanel}
                      disabled={openPanelCount === 1}
                      className="text-gray-400 hover:text-gray-600
                        disabled:opacity-30 disabled:cursor-not-allowed
                        transition-colors"
                      aria-label="Collapse code panel"
                    >
                      <span
                        className="hero-chevron-left size-3"
                        aria-hidden="true"
                      />
                    </button>
                  )}
                </div>
              </div>

              {/* Editor */}
              {!isCenterCollapsed && (
                <div className="flex-1 overflow-hidden">
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
                </div>
              )}
            </div>
          </Panel>

          {/* Resize Handle */}
          <PanelResizeHandle
            className="w-1 bg-gray-200 hover:bg-blue-400
            transition-colors cursor-col-resize"
          />

          {/* Right Panel - Placeholder for Run / Logs / Step I/O */}
          <Panel
            ref={rightPanelRef}
            defaultSize={1}
            minSize={5}
            collapsible
            collapsedSize={1}
            onCollapse={() => setIsRightCollapsed(true)}
            onExpand={() => setIsRightCollapsed(false)}
            className="bg-gray-50 border-l border-gray-200"
          >
            <div className="h-full flex flex-col">
              {/* Panel heading */}
              <div
                className={`shrink-0 transition-transform ${
                  isRightCollapsed ? "rotate-90" : ""
                }`}
              >
                <div className="flex items-center justify-between px-3 py-2">
                  <button
                    onClick={toggleRightPanel}
                    className="text-xs font-medium text-gray-400
                      uppercase tracking-wide hover:text-gray-600
                      transition-colors cursor-pointer"
                  >
                    Output
                  </button>
                  {!isRightCollapsed && (
                    <button
                      onClick={toggleRightPanel}
                      disabled={openPanelCount === 1}
                      className="text-gray-400 hover:text-gray-600
                        disabled:opacity-30 disabled:cursor-not-allowed
                        transition-colors"
                      aria-label="Collapse right panel"
                    >
                      <span
                        className="hero-chevron-right size-3"
                        aria-hidden="true"
                      />
                    </button>
                  )}
                </div>
              </div>

              {/* Panel content */}
              {!isRightCollapsed && (
                <div className="flex-1 p-4 flex items-center
                  justify-center">
                  <div className="text-center text-gray-500">
                    <p className="text-sm font-medium">
                      Run / Logs / Step I/O
                    </p>
                    <p className="text-xs mt-1">Coming Soon</p>
                  </div>
                </div>
              )}
            </div>
          </Panel>
        </PanelGroup>
      </div>
    </div>
  );
}
