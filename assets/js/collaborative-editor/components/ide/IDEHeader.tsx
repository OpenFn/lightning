import { useHotkeys } from "react-hotkeys-hook";

import { useURLState } from "#/react/lib/use-url-state";
import { buildClassicalEditorUrl } from "#/utils/editorUrlConversion";

import { useIsNewWorkflow } from "../../hooks/useSessionContext";
import { useVersionSelect } from "../../hooks/useVersionSelect";
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
  projectId: string | undefined;
  onClose: () => void;
  onSave: () => void;
  onRun: () => void;
  onRetry: () => void;
  isRetryable: boolean;
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
 *
 * Retry state is managed by ManualRunPanel and passed through FullScreenIDE.
 */
export function IDEHeader({
  jobId,
  jobName,
  jobAdaptor,
  jobCredentialId,
  snapshotVersion,
  latestSnapshotVersion,
  workflowId,
  projectId,
  onClose,
  onSave,
  onRun,
  onRetry,
  isRetryable,
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

  // Get URL state for building classical editor link
  const { searchParams } = useURLState();
  const isNewWorkflow = useIsNewWorkflow();

  // Handle Cmd/Ctrl+Enter for main action (Run or Retry based on state)
  useHotkeys(
    "mod+enter",
    e => {
      e.preventDefault();
      if (canRun && !isRunning) {
        if (isRetryable) {
          onRetry();
        } else {
          onRun();
        }
      }
    },
    {
      enabled: true,
      scopes: ["ide"],
    },
    [canRun, isRunning, isRetryable, onRetry, onRun]
  );

  // Handle Cmd/Ctrl+Shift+Enter to force new work order
  useHotkeys(
    "mod+shift+enter",
    e => {
      e.preventDefault();
      if (canRun && !isRunning && isRetryable) {
        // Force new work order even in retry mode
        onRun();
      }
    },
    {
      enabled: true,
      scopes: ["ide"],
    },
    [canRun, isRunning, isRetryable, onRun]
  );

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
                credentialId={jobCredentialId ?? null}
                size="sm"
                onEdit={onEditAdaptor}
                onChangeAdaptor={onChangeAdaptor}
              />
            </div>
          )}
          {projectId && workflowId && (
            <a
              href={(() => {
                // Build URL with current job selected and inspector open
                const params = new URLSearchParams(searchParams);
                params.set("job", jobId);
                params.set("panel", "editor");

                return buildClassicalEditorUrl({
                  projectId,
                  workflowId,
                  searchParams: params,
                  isNewWorkflow,
                });
              })()}
              className="inline-flex items-center justify-center flex-shrink-0
              w-6 h-6 text-primary-600 hover:text-primary-700
              hover:bg-primary-50 rounded transition-colors"
            >
              <Tooltip content="Switch back to classical editor" side="bottom">
                <span className="hero-beaker-solid h-4 w-4" />
              </Tooltip>
            </a>
          )}
        </div>

        {/* Right: Action buttons */}
        <div className="flex items-center gap-3">
          {!canRun && runTooltip ? (
            <Tooltip content={runTooltip} side="bottom">
              <span className="inline-block">
                <RunRetryButton
                  isRetryable={isRetryable}
                  isDisabled={!canRun}
                  isSubmitting={isRunning}
                  onRun={onRun}
                  onRetry={onRetry}
                  buttonText={{
                    run: "Run",
                    retry: "Run (retry)",
                    processing: "Processing",
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
              isSubmitting={isRunning}
              onRun={onRun}
              onRetry={onRetry}
              buttonText={{
                run: "Run",
                retry: "Run (retry)",
                processing: "Processing",
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
