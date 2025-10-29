import {
  DocumentIcon,
  PencilSquareIcon,
  QueueListIcon,
} from "@heroicons/react/24/outline";
import { useCallback, useEffect, useState } from "react";
import { useHotkeys } from "react-hotkeys-hook";

import { FilterTypes } from "../../manual-run-panel/types";
import CustomView from "../../manual-run-panel/views/CustomView";
import EmptyView from "../../manual-run-panel/views/EmptyView";
import ExistingView from "../../manual-run-panel/views/ExistingView";
import type { Dataclip } from "../api/dataclips";
import * as dataclipApi from "../api/dataclips";
import { useCanRun } from "../hooks/useWorkflow";
import { notifications } from "../lib/notifications";
import type { Workflow } from "../types/workflow";

import { Button } from "./Button";
import { InspectorFooter } from "./inspector/InspectorFooter";
import { InspectorLayout } from "./inspector/InspectorLayout";
import { SelectedDataclipView } from "./manual-run/SelectedDataclipView";
import { Tabs } from "./Tabs";

interface ManualRunPanelProps {
  workflow: Workflow;
  projectId: string;
  workflowId: string;
  jobId?: string | null;
  triggerId?: string | null;
  onClose: () => void;
  renderMode?: "standalone" | "embedded";
  onRunStateChange?: (
    canRun: boolean,
    isSubmitting: boolean,
    handleRun: () => void
  ) => void;
  saveWorkflow: () => Promise<{
    saved_at?: string;
    lock_version?: number;
  } | null>;
}

type TabValue = "empty" | "custom" | "existing";

export function ManualRunPanel({
  workflow,
  projectId,
  workflowId,
  jobId,
  triggerId,
  onClose,
  renderMode = "standalone",
  onRunStateChange,
  saveWorkflow,
}: ManualRunPanelProps) {
  const [selectedTab, setSelectedTab] = useState<TabValue>("empty");
  const [selectedDataclip, setSelectedDataclip] = useState<Dataclip | null>(
    null
  );
  const [dataclips, setDataclips] = useState<Dataclip[]>([]);
  const [searchQuery, setSearchQuery] = useState("");
  const [customBody, setCustomBody] = useState("{}");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [nextCronRunDataclipId, setNextCronRunDataclipId] = useState<
    string | null
  >(null);
  const [canEditDataclip, setCanEditDataclip] = useState(false);
  const [currentRunDataclip] = useState<Dataclip | null>(null);

  // Filter state for ExistingView
  const [selectedClipType, setSelectedClipType] = useState("");
  const [selectedDates, setSelectedDates] = useState({
    before: "",
    after: "",
  });
  const [namedOnly, setNamedOnly] = useState(false);

  // Use centralized canRun hook for workflow-level permissions
  const { canRun: canRunWorkflow, tooltipMessage: workflowRunTooltipMessage } =
    useCanRun();

  // Determine run context
  const runContext = jobId
    ? { type: "job" as const, id: jobId }
    : triggerId
      ? { type: "trigger" as const, id: triggerId }
      : {
          type: "trigger" as const,
          id: workflow.triggers[0]?.id,
        };

  // Get the node for panel title
  const contextJob =
    runContext.type === "job"
      ? workflow.jobs.find(j => j.id === runContext.id)
      : null;

  const contextTrigger =
    runContext.type === "trigger"
      ? workflow.triggers.find(t => t.id === runContext.id)
      : null;

  const panelTitle = contextJob
    ? `Run from ${contextJob.name}`
    : contextTrigger
      ? `Run from Trigger (${contextTrigger.type})`
      : "Run Workflow";

  // Watch for jobId/triggerId changes and update panel
  useEffect(() => {
    // Reset state when context changes
    setSelectedDataclip(null);
    setSearchQuery("");
    setSelectedClipType("");
    setSelectedDates({ before: "", after: "" });
    setNamedOnly(false);
  }, [jobId, triggerId]);

  // Fetch initial dataclips
  useEffect(() => {
    const contextId = runContext.id;
    if (!contextId) return;

    const fetchDataclips = async () => {
      try {
        const response = await dataclipApi.searchDataclips(
          projectId,
          contextId,
          "",
          {}
        );
        setDataclips(response.data);
        setNextCronRunDataclipId(response.next_cron_run_dataclip_id);
        setCanEditDataclip(response.can_edit_dataclip);

        // Auto-select next cron run dataclip if exists
        if (response.next_cron_run_dataclip_id) {
          const nextCronDataclip = response.data.find(
            d => d.id === response.next_cron_run_dataclip_id
          );
          if (nextCronDataclip) {
            setSelectedDataclip(nextCronDataclip);
            setSelectedTab("existing");
          }
        }
      } catch (error) {
        console.error("Failed to fetch dataclips:", error);
      }
    };

    void fetchDataclips();
  }, [projectId, runContext.id]);

  // Build filters object for API
  const buildFilters = useCallback(() => {
    const filters: Record<string, string> = {};
    if (selectedClipType) filters["type"] = selectedClipType;
    if (selectedDates.before) filters["before"] = selectedDates.before;
    if (selectedDates.after) filters["after"] = selectedDates.after;
    if (namedOnly) filters["named_only"] = "true";
    return filters;
  }, [selectedClipType, selectedDates.before, selectedDates.after, namedOnly]);

  // Get active filters for display
  const getActiveFilters = useCallback(() => {
    const filters: Record<string, string | undefined> = {};
    if (selectedClipType) filters[FilterTypes.DATACLIP_TYPE] = selectedClipType;
    if (selectedDates.before)
      filters[FilterTypes.BEFORE_DATE] = selectedDates.before;
    if (selectedDates.after)
      filters[FilterTypes.AFTER_DATE] = selectedDates.after;
    if (namedOnly) filters[FilterTypes.NAMED_ONLY] = "true";
    return filters;
  }, [selectedClipType, selectedDates.before, selectedDates.after, namedOnly]);

  // Clear filter handler
  const clearFilter = useCallback((filterType: FilterTypes) => {
    switch (filterType) {
      case FilterTypes.DATACLIP_TYPE:
        setSelectedClipType("");
        break;
      case FilterTypes.BEFORE_DATE:
        setSelectedDates(p => ({ ...p, before: "" }));
        break;
      case FilterTypes.AFTER_DATE:
        setSelectedDates(p => ({ ...p, after: "" }));
        break;
      case FilterTypes.NAMED_ONLY:
        setNamedOnly(false);
        break;
    }
  }, []);

  // Search handler
  const handleSearch = useCallback(async () => {
    const contextId = runContext.id;
    if (!contextId) return;

    try {
      const response = await dataclipApi.searchDataclips(
        projectId,
        contextId,
        searchQuery,
        buildFilters()
      );
      setDataclips(response.data);
    } catch (error) {
      console.error("Failed to search dataclips:", error);
    }
  }, [projectId, runContext.id, searchQuery, buildFilters]);

  // Auto-search when filters change (debounced)
  useEffect(() => {
    if (selectedTab !== "existing") return;

    const contextId = runContext.id;
    if (!contextId) return;

    // Debounce: wait 300ms after last filter change before searching
    const timeoutId = setTimeout(() => {
      const filters: Record<string, string> = {};
      if (selectedClipType) filters["type"] = selectedClipType;
      if (selectedDates.before) filters["before"] = selectedDates.before;
      if (selectedDates.after) filters["after"] = selectedDates.after;
      if (namedOnly) filters["named_only"] = "true";

      void dataclipApi
        .searchDataclips(projectId, contextId, searchQuery, filters)
        .then(response => {
          setDataclips(response.data);
          return response;
        })
        .catch(error => {
          console.error("Failed to search dataclips:", error);
        });
    }, 300);

    return () => clearTimeout(timeoutId);
  }, [
    selectedClipType,
    selectedDates.before,
    selectedDates.after,
    namedOnly,
    searchQuery,
    selectedTab,
    projectId,
    runContext.id,
  ]);

  const handleCustomBodyChange = useCallback((value: string) => {
    setCustomBody(value);
  }, []);

  const handleSelectDataclip = useCallback((dataclip: Dataclip) => {
    setSelectedDataclip(dataclip);
  }, []);

  const handleUnselectDataclip = useCallback(() => {
    setSelectedDataclip(null);
  }, []);

  const handleDataclipNameChange = useCallback(
    async (dataclipId: string, name: string | null) => {
      const response = await dataclipApi.updateDataclipName(
        projectId,
        dataclipId,
        name
      );

      // Update local state
      const updated = response.data;
      setSelectedDataclip(updated);
      setDataclips(prev => prev.map(d => (d.id === updated.id ? updated : d)));
    },
    [projectId]
  );

  const handleRun = useCallback(async () => {
    const contextId = runContext.id;
    if (!contextId) {
      console.error("No context ID available");
      return;
    }

    // Check workflow-level permissions before running
    if (!canRunWorkflow) {
      notifications.alert({
        title: "Cannot run workflow",
        description: workflowRunTooltipMessage,
      });
      return;
    }

    setIsSubmitting(true);
    try {
      // Save workflow first
      await saveWorkflow();

      const params: dataclipApi.ManualRunParams = {
        workflowId,
        projectId,
      };

      // Add job or trigger ID
      if (runContext.type === "job") {
        params.jobId = contextId;
      } else {
        params.triggerId = contextId;
      }

      // Add dataclip or custom body based on selected tab
      if (selectedTab === "existing" && selectedDataclip) {
        params.dataclipId = selectedDataclip.id;
      } else if (selectedTab === "custom") {
        params.customBody = customBody;
      }
      // For 'empty' tab, no dataclip or body needed

      const response = await dataclipApi.submitManualRun(params);

      // Navigate to run page
      window.location.href = `/projects/${projectId}/runs/${response.data.run_id}`;
    } catch (error) {
      console.error("Failed to submit run:", error);
      alert(error instanceof Error ? error.message : "Failed to submit run");
      setIsSubmitting(false);
    }
  }, [
    workflowId,
    projectId,
    runContext,
    selectedTab,
    selectedDataclip,
    customBody,
    saveWorkflow,
    canRunWorkflow,
    workflowRunTooltipMessage,
  ]);

  // Combine workflow-level permissions with local validation
  // Local validation: user must have selected valid input (empty, custom, or existing dataclip)
  const hasValidInput =
    selectedTab === "empty" ||
    (selectedTab === "existing" && !!selectedDataclip) ||
    selectedTab === "custom";

  const canRun = canRunWorkflow && hasValidInput;

  // Notify parent of run state changes (for embedded mode)
  useEffect(() => {
    if (onRunStateChange) {
      onRunStateChange(canRun, isSubmitting, handleRun);
    }
  }, [canRun, isSubmitting, handleRun, onRunStateChange]);

  // Handle Escape key to close the run panel
  useHotkeys(
    "escape",
    () => {
      onClose();
    },
    { enabled: true, enableOnFormTags: true },
    [onClose]
  );

  // Extract content for reuse
  const content = selectedDataclip ? (
    <SelectedDataclipView
      dataclip={selectedDataclip}
      onUnselect={handleUnselectDataclip}
      onNameChange={handleDataclipNameChange}
      canEdit={canEditDataclip}
      isNextCronRun={nextCronRunDataclipId === selectedDataclip.id}
    />
  ) : (
    <div className="flex flex-col h-full overflow-hidden">
      <Tabs
        value={selectedTab}
        onChange={value => setSelectedTab(value)}
        options={[
          { value: "empty", label: "Empty", icon: DocumentIcon },
          {
            value: "custom",
            label: "Custom",
            icon: PencilSquareIcon,
          },
          {
            value: "existing",
            label: "Existing",
            icon: QueueListIcon,
          },
        ]}
      />

      {selectedTab === "empty" && <EmptyView />}
      {selectedTab === "custom" && (
        <CustomView
          pushEvent={(_event, data) => {
            if (data?.manual?.body !== undefined) {
              handleCustomBodyChange(data.manual.body);
            }
          }}
        />
      )}
      {selectedTab === "existing" && (
        <ExistingView
          dataclips={dataclips}
          query={searchQuery}
          setQuery={setSearchQuery}
          setSelected={handleSelectDataclip}
          filters={getActiveFilters()}
          selectedClipType={selectedClipType}
          setSelectedClipType={setSelectedClipType}
          clearFilter={clearFilter}
          selectedDates={selectedDates}
          setSelectedDates={setSelectedDates}
          namedOnly={namedOnly}
          setNamedOnly={setNamedOnly}
          onSubmit={handleSearch}
          fixedHeight={true}
          currentRunDataclip={currentRunDataclip}
          nextCronRunDataclipId={nextCronRunDataclipId}
        />
      )}
    </div>
  );

  // Embedded mode: return content without wrapper
  if (renderMode === "embedded") {
    return content;
  }

  // Standalone mode: wrap in InspectorLayout
  return (
    <InspectorLayout
      title={panelTitle}
      nodeType={runContext.type === "job" ? "job" : "trigger"}
      onClose={onClose}
      footer={
        <InspectorFooter
          leftButtons={
            <Button
              variant="primary"
              onClick={handleRun}
              disabled={!canRun || isSubmitting}
            >
              {isSubmitting ? "Running..." : "Run Workflow Now"}
            </Button>
          }
        />
      }
    >
      {content}
    </InspectorLayout>
  );
}
