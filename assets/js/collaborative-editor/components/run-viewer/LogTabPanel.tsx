import { useEffect, useRef, useState } from "react";

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
    console.log("[LogTabPanel] Mount effect running", {
      hasContainer: !!containerRef.current,
      alreadyMounted: mountedRef.current,
      containerHeight: containerRef.current?.offsetHeight,
      containerWidth: containerRef.current?.offsetWidth,
    });

    if (!containerRef.current) {
      console.warn("[LogTabPanel] No container ref!");
      return;
    }

    // Prevent double-mounting in React Strict Mode
    if (mountedRef.current) {
      console.log("[LogTabPanel] Already mounted (strict mode), skipping");
      return;
    }

    // Check if container has dimensions
    const height = containerRef.current.offsetHeight;
    const width = containerRef.current.offsetWidth;
    console.log("[LogTabPanel] Container dimensions:", { height, width });

    if (height === 0 || width === 0) {
      console.error(
        "[LogTabPanel] Container has no dimensions! Height:",
        height,
        "Width:",
        width
      );
    }

    console.log("[LogTabPanel] Mounting log viewer...");
    try {
      mountedRef.current = true;
      viewerInstanceRef.current = mountLogViewer(
        containerRef.current,
        storeRef.current
      );
      console.log("[LogTabPanel] Log viewer mounted successfully!");
    } catch (error) {
      console.error("[LogTabPanel] Failed to mount log viewer:", error);
      mountedRef.current = false;
    }

    return () => {
      console.log(
        "[LogTabPanel] Cleanup - NOT unmounting (keeping mounted for strict mode)"
      );
      // Don't actually unmount - let the component stay mounted
      // Only unmount when the component is truly destroyed
    };
  }, []);

  // Update selected step in log store
  useEffect(() => {
    storeRef.current.getState().setStepId(selectedStepId ?? undefined);
  }, [selectedStepId]);

  // Subscribe to log events via existing run channel
  useEffect(() => {
    if (!run || !provider?.socket) return undefined;

    const channels = (provider.socket as any).channels;
    console.log("[LogTabPanel] Available channels:", channels);
    const channel = channels?.find((ch: any) => ch.topic === `run:${run.id}`);

    if (!channel) {
      console.warn("[LogTabPanel] Run channel not found for logs", {
        runId: run.id,
        availableChannels: channels?.map((ch: any) => ch.topic),
      });
      return undefined;
    }

    console.log("[LogTabPanel] Found channel for run:", run.id);

    // Fetch initial logs
    void channelRequest<{ logs: unknown }>(channel, "fetch:logs", {})
      .then(response => {
        console.log("[LogTabPanel] Received logs from fetch:logs:", response);

        if (!response.logs) {
          console.warn("[LogTabPanel] No logs in response", response);
          return;
        }

        if (!Array.isArray(response.logs)) {
          console.error(
            "[LogTabPanel] Logs is not an array:",
            typeof response.logs,
            response.logs
          );
          return;
        }

        console.log("[LogTabPanel] Logs array length:", response.logs.length);
        console.log("[LogTabPanel] First log (if any):", response.logs[0]);

        if (response.logs.length > 0) {
          console.log(
            "[LogTabPanel] Timestamp type:",
            typeof (response.logs[0] as any)?.timestamp
          );
        }

        const logStore = storeRef.current.getState();
        console.log(
          "[LogTabPanel] Current log lines before add:",
          logStore.logLines.length
        );

        logStore.addLogLines(response.logs as any);

        console.log(
          "[LogTabPanel] Current log lines after add:",
          storeRef.current.getState().logLines.length
        );
        console.log(
          "[LogTabPanel] Formatted log lines:",
          storeRef.current.getState().formattedLogLines
        );
      })
      .catch(error => {
        console.error("[LogTabPanel] Failed to fetch logs", error);
      });

    // Listen for new logs
    const logHandler = (payload: { logs: unknown[] }) => {
      console.log("[LogTabPanel] Received logs from 'logs' event:", payload);
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
    <div className="h-full flex">
      {/* Step list for navigation */}
      <div className="w-48 border-r overflow-auto p-2">
        <StepList
          steps={run.steps}
          selectedStepId={selectedStepId}
          onSelectStep={runStore.selectStep}
        />
      </div>

      {/* Log viewer with filter */}
      <div className="flex-1 flex flex-col rounded-md bg-slate-700 font-mono text-gray-200">
        {/* Log level filter header */}
        <div className="border-b border-slate-500">
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
        <div ref={containerRef} className="flex-1" />
      </div>
    </div>
  );
}
