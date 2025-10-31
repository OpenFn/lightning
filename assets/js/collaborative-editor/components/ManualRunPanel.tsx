import {
  DocumentIcon,
  PencilSquareIcon,
  QueueListIcon,
} from "@heroicons/react/24/outline";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useHotkeys } from "react-hotkeys-hook";

import { cn } from "#/utils/cn";
import _logger from "#/utils/logger";

import { FilterTypes } from "../../manual-run-panel/types";
import CustomView from "../../manual-run-panel/views/CustomView";
import EmptyView from "../../manual-run-panel/views/EmptyView";
import ExistingView from "../../manual-run-panel/views/ExistingView";
import { useURLState } from "../../react/lib/use-url-state";
import type { Dataclip } from "../api/dataclips";
import * as dataclipApi from "../api/dataclips";
import { useCanRun } from "../hooks/useWorkflow";
import { getCsrfToken } from "../lib/csrf";
import { notifications } from "../lib/notifications";
import type { Workflow } from "../types/workflow";

import { InspectorFooter } from "./inspector/InspectorFooter";
import { InspectorLayout } from "./inspector/InspectorLayout";
import { SelectedDataclipView } from "./manual-run/SelectedDataclipView";
import { RunRetryButton } from "./RunRetryButton";
import { Tabs } from "./Tabs";

const logger = _logger.ns("ManualRunPanel").seal();

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
  onRunSubmitted?: (runId: string) => void;
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
  onRunSubmitted,
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

  // Retry state tracking
  const { searchParams } = useURLState();
  const followedRunId = searchParams.get("run"); // 'run' param is run ID
  const [followedRunStep, setFollowedRunStep] = useState<{
    id: string;
    input_dataclip_id: string | null;
  } | null>(null);

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

  // For triggers, we need to find the first connected job for dataclip fetching
  // since dataclips are associated with jobs, not triggers
  // This mirrors the backend logic in WorkflowController.get_selected_job
  const dataclipJobId = useMemo(() => {
    if (runContext.type === "job") {
      return runContext.id;
    }

    // Find the first edge from this trigger to a job
    const triggerEdge = workflow.edges.find(
      edge => edge.source_trigger_id === runContext.id
    );

    return triggerEdge?.target_job_id || workflow.jobs[0]?.id;
  }, [runContext, workflow.edges, workflow.jobs]);

  // Watch for jobId/triggerId changes and update panel
  useEffect(() => {
    // Reset state when context changes
    setSelectedDataclip(null);
    setSearchQuery("");
    setSelectedClipType("");
    setSelectedDates({ before: "", after: "" });
    setNamedOnly(false);
  }, [jobId, triggerId]);

  // Fetch step data for followed run to determine retry eligibility
  useEffect(() => {
    if (!followedRunId || !dataclipJobId) {
      setFollowedRunStep(null);
      return;
    }

    const fetchStepData = async () => {
      try {
        const response = await fetch(
          `/projects/${projectId}/runs/${followedRunId}/steps?job_id=${dataclipJobId}`,
          {
            credentials: "same-origin",
          }
        );

        if (!response.ok) {
          if (response.status === 404) {
            // No step found for this job - not retryable
            setFollowedRunStep(null);
            return;
          }
          throw new Error(`Failed to fetch step data: ${response.statusText}`);
        }

        const result = (await response.json()) as {
          data: { id: string; input_dataclip_id: string | null };
        };
        setFollowedRunStep(result.data);
      } catch (error) {
        logger.error("Failed to fetch step data:", error);
        setFollowedRunStep(null);
      }
    };

    void fetchStepData();
  }, [followedRunId, dataclipJobId, projectId]);

  // Fetch initial dataclips
  useEffect(() => {
    if (!dataclipJobId) return;

    const fetchDataclips = async () => {
      try {
        const response = await dataclipApi.searchDataclips(
          projectId,
          dataclipJobId,
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
        logger.error("Failed to fetch dataclips:", error);
      }
    };

    void fetchDataclips();
  }, [projectId, dataclipJobId]);

  // Auto-select step's input dataclip when following a run
  useEffect(() => {
    if (!followedRunStep?.input_dataclip_id || !dataclips.length) {
      return;
    }

    // Find the step's input dataclip in the loaded dataclips
    const stepDataclip = dataclips.find(
      dc => dc.id === followedRunStep.input_dataclip_id
    );

    if (stepDataclip) {
      setSelectedDataclip(stepDataclip);
      setSelectedTab("existing");
    }
  }, [followedRunStep, dataclips]);

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
    if (!dataclipJobId) return;

    try {
      const response = await dataclipApi.searchDataclips(
        projectId,
        dataclipJobId,
        searchQuery,
        buildFilters()
      );
      setDataclips(response.data);
    } catch (error) {
      logger.error("Failed to search dataclips:", error);
    }
  }, [projectId, dataclipJobId, searchQuery, buildFilters]);

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
          logger.error("Failed to search dataclips:", error);
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
      logger.error("No context ID available");
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

      // Step 5: Invoke callback with run_id (stay in IDE, don't navigate)
      if (onRunSubmitted) {
        onRunSubmitted(response.data.run_id);
      } else {
        // Fallback: navigate away if no callback (for standalone mode)
        window.location.href = `/projects/${projectId}/runs/${response.data.run_id}`;
      }

      // Reset submitting state after successful submission
      setIsSubmitting(false);
    } catch (error) {
      logger.error("Failed to submit run:", error);
      notifications.alert({
        title: "Failed to submit run",
        description:
          error instanceof Error ? error.message : "An unknown error occurred",
      });
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
    onRunSubmitted,
  ]);

  const handleRetry = useCallback(async () => {
    if (!followedRunId || !followedRunStep) {
      logger.error("Cannot retry: missing run or step data");
      return;
    }

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

      // Call retry endpoint
      const csrfToken = getCsrfToken();
      const response = await fetch(
        `/projects/${projectId}/runs/${followedRunId}/retry`,
        {
          method: "POST",
          credentials: "same-origin",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": csrfToken || "",
          },
          body: JSON.stringify({ step_id: followedRunStep.id }),
        }
      );

      if (!response.ok) {
        const error = (await response.json()) as { error?: string };
        throw new Error(error.error || "Failed to retry run");
      }

      const result = (await response.json()) as {
        data: { run_id: string };
      };

      notifications.success({
        title: "Retry started",
        description: "Your workflow retry is now running",
      });

      // Invoke callback with new run_id
      if (onRunSubmitted) {
        onRunSubmitted(result.data.run_id);
      } else {
        // Fallback: navigate to new run
        window.location.href = `/projects/${projectId}/runs/${result.data.run_id}`;
      }
    } catch (error) {
      logger.error("Failed to retry run:", error);
      notifications.alert({
        title: "Retry failed",
        description: error instanceof Error ? error.message : "Unknown error",
      });
      setIsSubmitting(false);
    }
  }, [
    followedRunId,
    followedRunStep,
    canRunWorkflow,
    workflowRunTooltipMessage,
    saveWorkflow,
    projectId,
    onRunSubmitted,
  ]);

  // Calculate retry eligibility
  const isRetryable = useMemo(() => {
    if (!followedRunId || !followedRunStep || !selectedDataclip) {
      return false;
    }

    return (
      selectedDataclip.wiped_at === null &&
      followedRunStep.input_dataclip_id === selectedDataclip.id
    );
  }, [followedRunId, followedRunStep, selectedDataclip]);

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
      // Wrap handleRun to avoid promise warnings in parent components
      const wrappedHandleRun = () => {
        void handleRun();
      };
      onRunStateChange(canRun, isSubmitting, wrappedHandleRun);
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

  // Handle ⌘+Enter for main action (Run or Retry based on state)
  useHotkeys(
    "mod+enter",
    e => {
      e.preventDefault();
      if (canRun && !isSubmitting) {
        if (isRetryable) {
          void handleRetry();
        } else {
          void handleRun();
        }
      }
    },
    {
      enabled: true,
      enableOnFormTags: true,
    },
    [canRun, isSubmitting, isRetryable, handleRetry, handleRun]
  );

  // Handle ⌘+Shift+Enter for force new work order
  useHotkeys(
    "mod+shift+enter",
    e => {
      e.preventDefault();
      if (canRun && !isSubmitting && isRetryable) {
        // Force new work order even in retry mode
        void handleRun();
      }
    },
    {
      enabled: true,
      enableOnFormTags: true,
    },
    [canRun, isSubmitting, isRetryable, handleRun]
  );

  // Extract content for reuse
  const content = selectedDataclip ? (
    <SelectedDataclipView
      dataclip={selectedDataclip}
      onUnselect={handleUnselectDataclip}
      onNameChange={handleDataclipNameChange}
      canEdit={canEditDataclip}
      isNextCronRun={nextCronRunDataclipId === selectedDataclip.id}
      renderMode={renderMode}
    />
  ) : (
    <div
      className={cn(
        "flex flex-col h-full overflow-hidden",
        renderMode === "embedded" ? "mt-2" : "mt-4"
      )}
    >
      <Tabs
        className="mx-3"
        variant="pills"
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
          pushEvent={(_event, data: unknown) => {
            // Type guard for data shape
            if (
              data &&
              typeof data === "object" &&
              "manual" in data &&
              data.manual &&
              typeof data.manual === "object" &&
              "body" in data.manual &&
              typeof data.manual.body === "string"
            ) {
              handleCustomBodyChange(data.manual.body);
            }
          }}
          renderMode={renderMode}
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
          onSubmit={() => {
            void handleSearch();
          }}
          fixedHeight={true}
          currentRunDataclip={currentRunDataclip}
          nextCronRunDataclipId={nextCronRunDataclipId}
          renderMode={renderMode}
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
      onClose={onClose}
      fixedHeight={true}
      showBackButton={true}
      footer={
        <InspectorFooter
          rightButtons={
            <RunRetryButton
              isRetryable={isRetryable}
              isDisabled={!canRun}
              isSubmitting={isSubmitting}
              onRun={() => {
                void handleRun();
              }}
              onRetry={() => {
                void handleRetry();
              }}
              buttonText={{
                run: "Run Workflow Now",
                retry: "Run (retry)",
                processing: "Running...",
              }}
            />
          }
        />
      }
    >
      {content}
    </InspectorLayout>
  );
}
