import { useVersionSelect } from "../../hooks/useVersionSelect";
import { AdaptorDisplay } from "../AdaptorDisplay";
import { Button } from "../Button";
import { Tooltip } from "../Tooltip";
import { VersionDropdown } from "../VersionDropdown";

interface IDEHeaderProps {
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
  return (
    <div className="shrink-0 border-b border-gray-200 bg-white px-4 py-2">
      <div className="flex items-center justify-between gap-4">
        {/* Left: Job name with version chip and adaptor display */}
        <div className="flex items-center gap-4 flex-1 min-w-0">
          <div className="flex-shrink-0">
            <h2 className="text-base font-semibold text-gray-900 whitespace-nowrap">
              {jobName}
            </h2>
          </div>
          {workflowId && (
            <div className="flex-shrink-0">
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
          <Tooltip content={runTooltip || "Run workflow"} side="bottom">
            <span className="inline-block">
              <Button variant="secondary" onClick={onRun} disabled={!canRun}>
                <span
                  className="hero-play size-4 inline-block mr-1"
                  aria-hidden="true"
                />
                {isRunning ? "Running..." : "Run"}
              </Button>
            </span>
          </Tooltip>

          <Tooltip content={saveTooltip} side="bottom">
            <span className="inline-block">
              <Button variant="secondary" onClick={onSave} disabled={!canSave}>
                <span
                  className="hero-check size-4 inline-block mr-1"
                  aria-hidden="true"
                />
                Save
              </Button>
            </span>
          </Tooltip>

          <Button
            variant="secondary"
            onClick={onClose}
            aria-label="Close full-screen editor"
          >
            <span
              className="hero-x-mark size-4 inline-block mr-1"
              aria-hidden="true"
            />
            Close
          </Button>
        </div>
      </div>
    </div>
  );
}
