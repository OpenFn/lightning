import { useEffect, useRef, useState } from "react";
import { Panel, PanelGroup, PanelResizeHandle } from "react-resizable-panels";

import { mount as mountLogViewer } from "../../../log-viewer/component";
import { createLogStore } from "../../../log-viewer/store";
import { channelRequest } from "../../hooks/useChannel";
import {
  useCurrentRun,
  useRunStoreInstance,
  useSelectedStepId,
} from "../../hooks/useRun";
import { useSession } from "../../hooks/useSession";
import { LogLevelFilter } from "./LogLevelFilter";
import { StepList } from "./StepList";

export function LogTabPanel() {
  const run = useCurrentRun();
  const selectedStepId = useSelectedStepId();
  const runStore = useRunStoreInstance();
  const { provider } = useSession();

  const containerRef = useRef<HTMLDivElement>(null);
  const storeRef = useRef(createLogStore());
  const viewerInstanceRef = useRef<ReturnType<typeof mountLogViewer> | null>(
    null
  );
  const mountedRef = useRef(false);

  // Track log level state from store
  const [logLevel, setLogLevel] = useState<"debug" | "info" | "warn" | "error">(
    () => storeRef.current.getState().desiredLogLevel as any
  );

  // Handle log level change
  const handleLogLevelChange = (
    newLevel: "debug" | "info" | "warn" | "error"
  ) => {
    storeRef.current.getState().setDesiredLogLevel(newLevel);
    setLogLevel(newLevel);
  };

  // Mount log viewer on first render
  useEffect(() => {
    if (!containerRef.current) {
      return;
    }

    // Prevent double-mounting in React Strict Mode
    if (mountedRef.current) {
      return;
    }

    try {
      mountedRef.current = true;
      viewerInstanceRef.current = mountLogViewer(
        containerRef.current,
        storeRef.current
      );
    } catch (error) {
      console.error("[LogTabPanel] Failed to mount log viewer:", error);
      mountedRef.current = false;
    }

    return () => {
      // Don't actually unmount - let the component stay mounted
      // Only unmount when the component is truly destroyed
    };
  }, []);

  // Handle Monaco resize when panel is resized
  useEffect(() => {
    if (!containerRef.current || !viewerInstanceRef.current) {
      return;
    }

    const resizeObserver = new ResizeObserver(() => {
      // Monaco's layout method handles resize
      const monaco = viewerInstanceRef.current?.monaco;
      if (monaco) {
        monaco.layout();
      }
    });

    resizeObserver.observe(containerRef.current);

    return () => {
      resizeObserver.disconnect();
    };
  }, []);

  // Update selected step in log store
  useEffect(() => {
    storeRef.current.getState().setStepId(selectedStepId ?? undefined);
  }, [selectedStepId]);

  // Subscribe to log events via existing run channel
  useEffect(() => {
    if (!run || !provider?.socket) {
      return undefined;
    }

    const channels = (provider.socket as any).channels;
    const channel = channels?.find((ch: any) => ch.topic === `run:${run.id}`);

    if (!channel) {
      console.warn("[LogTabPanel] Run channel not found for logs", {
        runId: run.id,
      });
      return undefined;
    }

    // Fetch initial logs
    void channelRequest<{ logs: unknown }>(channel, "fetch:logs", {})
      .then(response => {
        if (!response.logs || !Array.isArray(response.logs)) {
          return;
        }

        const logStore = storeRef.current.getState();
        logStore.addLogLines(response.logs as any);
      })
      .catch(error => {
        console.error("[LogTabPanel] Failed to fetch logs", error);
      });

    // Listen for new logs
    const logHandler = (payload: { logs: unknown[] }) => {
      const logStore = storeRef.current.getState();
      logStore.addLogLines(payload.logs as any);
    };

    channel.on("logs", logHandler);

    return () => {
      channel.off("logs", logHandler);
    };
  }, [run, provider]);

  if (!run) {
    return <div className="p-4 text-gray-500">No run selected</div>;
  }

  return (
    <PanelGroup direction="vertical" className="h-full">
      {/* Step list for navigation */}
      <Panel defaultSize={20} minSize={10} maxSize={40}>
        <div className="h-full overflow-auto border-b p-4">
          <StepList
            steps={run.steps}
            selectedStepId={selectedStepId}
            onSelectStep={runStore.selectStep}
          />
        </div>
      </Panel>

      {/* Resize handle */}
      <PanelResizeHandle className="h-1 bg-gray-200 hover:bg-blue-400 transition-colors cursor-row-resize" />

      {/* Log viewer with filter */}
      <Panel minSize={30}>
        <div className="flex h-full flex-col rounded-md bg-slate-700 font-mono text-gray-200">
          {/* Log level filter header */}
          <div className="flex-none border-b border-slate-500">
            <div className="mx-auto px-2">
              <div className="flex h-6 flex-row-reverse items-center">
                <LogLevelFilter
                  selectedLevel={logLevel}
                  onLevelChange={handleLogLevelChange}
                />
              </div>
            </div>
          </div>

          {/* Log viewer */}
          <div ref={containerRef} className="flex-1 overflow-hidden" />
        </div>
      </Panel>
    </PanelGroup>
  );
}
