import { useCallback, useEffect, useMemo, useState } from "react";

import { useURLState } from "#/react/lib/use-url-state";

import { useProject } from "../../hooks/useSessionContext";
import { useVersionSelect } from "../../hooks/useVersionSelect";
import { getCsrfToken } from "../../lib/csrf";
import { notifications } from "../../lib/notifications";
import { AdaptorDisplay } from "../AdaptorDisplay";
import { Button } from "../Button";
import { RunRetryButton } from "../RunRetryButton";
import { Tooltip } from "../Tooltip";
import { VersionDropdown } from "../VersionDropdown";

interface IDEHeaderProps {
  jobId: string;
  jobName: string;
  jobAdaptor?: string | undefined;
  jobCredentialId?: string | null | undefined;
  snapshotVersion: number | null | undefined;
  latestSnapshotVersion: number | null | undefined;
  workflowId: string | undefined;
  onClose: () => void;
  onSave: () => void;
  onRun: () => void;
  canRun: boolean;
  isRunning: boolean;
  canSave: boolean;
  saveTooltip: string;
  runTooltip?: string | undefined;
  onEditAdaptor?: (() => void) | undefined;
  onChangeAdaptor?: (() => void) | undefined;
}

/**
 * IDE Header component with job name and action buttons
 *
 * Displays job name on left, Run/Save/Close buttons on right.
 * Run triggers workflow execution from ManualRunPanel.
 * Save is wired to workflow save functionality.
 */
export function IDEHeader({
  jobId,
  jobName,
  jobAdaptor,
  jobCredentialId,
  snapshotVersion,
  latestSnapshotVersion,
  workflowId,
  onClose,
  onSave,
  onRun,
  canRun,
  isRunning,
  canSave,
  saveTooltip,
  runTooltip,
  onEditAdaptor,
  onChangeAdaptor,
}: IDEHeaderProps) {
  // Use shared version selection handler (destroys Y.Doc before switching)
  const handleVersionSelect = useVersionSelect();

  // URL state for followed run
  const { searchParams, updateSearchParams } = useURLState();
  const followedRunId = searchParams.get("run");

  // Get project context for API calls
  const project = useProject();
  const projectId = project?.id;

  // Retry state tracking
  const [isRetrying, setIsRetrying] = useState(false);
  const [followedRunStep, setFollowedRunStep] = useState<{
    id: string;
    input_dataclip_id: string | null;
  } | null>(null);

  // Fetch step data for followed run to determine retry eligibility
  useEffect(() => {
    if (!followedRunId || !projectId) {
      setFollowedRunStep(null);
      return;
    }

    const fetchStepData = async () => {
      try {
        const response = await fetch(
          `/projects/${projectId}/runs/${followedRunId}/steps?job_id=${jobId}`,
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
        console.error("Failed to fetch step data:", error);
        setFollowedRunStep(null);
      }
    };

    void fetchStepData();
  }, [followedRunId, jobId, projectId]);

  const handleRetry = useCallback(async () => {
    if (!followedRunId || !followedRunStep || !projectId) {
      console.error("Cannot retry: missing run or step data");
      return;
    }

    setIsRetrying(true);
    try {
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

      // Update URL to follow the new run
      updateSearchParams({ run: result.data.run_id });
    } catch (error) {
      console.error("Failed to retry run:", error);
      notifications.alert({
        title: "Retry failed",
        description: error instanceof Error ? error.message : "Unknown error",
      });
    } finally {
      setIsRetrying(false);
    }
  }, [followedRunId, followedRunStep, projectId, updateSearchParams]);

  // Calculate retry eligibility
  // A run is retryable if we have step data with an input dataclip
  const isRetryable = useMemo(() => {
    return Boolean(
      followedRunId && followedRunStep && followedRunStep.input_dataclip_id
    );
  }, [followedRunId, followedRunStep]);

  return (
    <div className="shrink-0 border-b border-gray-200 bg-white px-4 py-2">
      <div className="flex items-center justify-between gap-4">
        {/* Left: Job name with version chip and adaptor display */}
        <div className="flex items-center gap-4 flex-1 min-w-0">
          <div className="flex-shrink-0 flex items-center">
            <h2 className="text-base font-semibold text-gray-900 whitespace-nowrap">
              {jobName}
            </h2>
          </div>
          {workflowId && (
            <div className="flex-shrink-0 mb-0.5">
              <VersionDropdown
                currentVersion={snapshotVersion ?? null}
                latestVersion={latestSnapshotVersion ?? null}
                onVersionSelect={handleVersionSelect}
              />
            </div>
          )}
          {jobAdaptor && (
            <div className="flex-1 max-w-xs">
              <AdaptorDisplay
                adaptor={jobAdaptor}
                credentialId={jobCredentialId}
                size="sm"
                onEdit={onEditAdaptor}
                onChangeAdaptor={onChangeAdaptor}
              />
            </div>
          )}
        </div>

        {/* Right: Action buttons */}
        <div className="flex items-center gap-3">
          {runTooltip ? (
            <Tooltip content={runTooltip} side="bottom">
              <span className="inline-block">
                <RunRetryButton
                  isRetryable={isRetryable}
                  isDisabled={!canRun}
                  isSubmitting={isRetrying}
                  onRun={onRun}
                  onRetry={() => void handleRetry()}
                  buttonText={{
                    run: "Run",
                    retry: "Run (retry)",
                    processing: "Retrying...",
                  }}
                  variant="secondary"
                  dropdownPosition="down"
                />
              </span>
            </Tooltip>
          ) : (
            <RunRetryButton
              isRetryable={isRetryable}
              isDisabled={!canRun}
              isSubmitting={isRetrying}
              onRun={onRun}
              onRetry={() => void handleRetry()}
              buttonText={{
                run: "Run",
                retry: "Run (retry)",
                processing: "Retrying...",
              }}
              variant="secondary"
              dropdownPosition="down"
            />
          )}

          <Tooltip content={saveTooltip} side="bottom">
            <span className="inline-block">
              <Button variant="primary" onClick={onSave} disabled={!canSave}>
                Save
              </Button>
            </span>
          </Tooltip>

          <Button
            variant="nakedClose"
            onClick={onClose}
            aria-label="Close full-screen editor"
          />
        </div>
      </div>
    </div>
  );
}
