import { useEffect, useState } from "react";

import {
  useCurrentRun,
  useRunError,
  useRunLoading,
  useRunStoreInstance,
} from "../../hooks/useRun";
import { useSession } from "../../hooks/useSession";
import { Tabs } from "../Tabs";
import { InputTabPanel } from "./InputTabPanel";
import { LogTabPanel } from "./LogTabPanel";
import { OutputTabPanel } from "./OutputTabPanel";
import { RunTabPanel } from "./RunTabPanel";
import { RunSkeleton } from "./RunSkeleton";

type TabValue = "run" | "log" | "input" | "output";

interface RunViewerPanelProps {
  followRunId: string | null;
  onClearFollowRun?: () => void;
}

export function RunViewerPanel({ followRunId }: RunViewerPanelProps) {
  const [activeTab, setActiveTab] = useState<TabValue>("run");
  const runStore = useRunStoreInstance();
  const run = useCurrentRun();
  const isLoading = useRunLoading();
  const error = useRunError();
  const { provider } = useSession();

  // Connect to run channel when followRunId changes
  useEffect(() => {
    if (!followRunId || !provider) {
      runStore._disconnectFromRun();
      return;
    }

    const cleanup = runStore._connectToRun(provider, followRunId);
    return cleanup;
  }, [followRunId, provider, runStore]);

  // Persist active tab to localStorage
  useEffect(() => {
    if (activeTab) {
      localStorage.setItem("lightning.ide-run-viewer-tab", activeTab);
    }
  }, [activeTab]);

  // Restore tab from localStorage on mount
  useEffect(() => {
    const savedTab = localStorage.getItem("lightning.ide-run-viewer-tab");
    if (savedTab && ["run", "log", "input", "output"].includes(savedTab)) {
      setActiveTab(savedTab as TabValue);
    }
  }, []);

  // Empty state - no run to display
  if (!followRunId) {
    return (
      <div className="w-1/2 h-16 text-center m-auto p-4">
        <div className="text-gray-500 pb-2">
          After you click run, the logs and output will be visible here.
        </div>
      </div>
    );
  }

  // Loading state
  if (isLoading && !run) {
    return <RunSkeleton />;
  }

  // Error state
  if (error) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-center text-red-600">
          <p className="font-semibold">Error loading run</p>
          <p className="text-sm mt-1">{error}</p>
          <button
            onClick={() => runStore.clearError()}
            className="mt-4 px-4 py-2 bg-red-100
              hover:bg-red-200 rounded text-sm"
          >
            Dismiss
          </button>
        </div>
      </div>
    );
  }

  // No run data yet (shouldn't happen but defensive)
  if (!run) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-gray-500">No run data available</div>
      </div>
    );
  }

  return (
    <div
      className="h-full flex flex-col"
      role="region"
      aria-label="Run output viewer"
    >
      {/* Tab navigation */}
      <Tabs
        value={activeTab}
        onChange={setActiveTab}
        options={[
          { value: "run", label: "Run" },
          { value: "log", label: "Log" },
          { value: "input", label: "Input" },
          { value: "output", label: "Output" },
        ]}
      />

      {/* Tab content */}
      <div className="flex-1 overflow-hidden">
        {activeTab === "run" && <RunTabPanel />}
        {activeTab === "log" && <LogTabPanel />}
        {activeTab === "input" && <InputTabPanel />}
        {activeTab === "output" && <OutputTabPanel />}
      </div>
    </div>
  );
}
