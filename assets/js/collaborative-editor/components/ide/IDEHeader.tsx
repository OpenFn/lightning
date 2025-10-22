import { Button } from "../Button";
import { Tooltip } from "../Tooltip";

interface IDEHeaderProps {
  jobName: string;
  onClose: () => void;
  onSave: () => void;
  onRun: () => void;
  canSave: boolean;
  saveTooltip: string;
}

/**
 * IDE Header component with job name and action buttons
 *
 * Displays job name on left, Run/Save/Close buttons on right.
 * Run is disabled placeholder for future features.
 * Save is wired to workflow save functionality.
 */
export function IDEHeader({
  jobName,
  onClose,
  onSave,
  onRun,
  canSave,
  saveTooltip,
}: IDEHeaderProps) {
  return (
    <div
      className="shrink-0 border-b border-gray-200 bg-white px-6 py-3"
    >
      <div className="flex items-center justify-between">
        {/* Left: Job name */}
        <div>
          <h2 className="text-base font-semibold text-gray-900">
            {jobName}
          </h2>
          <p className="text-xs text-gray-500 mt-0.5">
            Full-screen editor
          </p>
        </div>

        {/* Right: Action buttons */}
        <div className="flex items-center gap-3">
          <Button
            variant="secondary"
            onClick={onRun}
            disabled
            className="opacity-50"
          >
            <span
              className="hero-play size-4 inline-block mr-1"
              aria-hidden="true"
            />
            Run
          </Button>

          <Tooltip content={saveTooltip} side="bottom">
            <span className="inline-block">
              <Button
                variant="secondary"
                onClick={onSave}
                disabled={!canSave}
              >
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
