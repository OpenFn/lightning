import { Button } from "../Button";

interface IDEHeaderProps {
  jobName: string;
  onClose: () => void;
  onSave: () => void;
  onRun: () => void;
}

/**
 * IDE Header component with job name and action buttons
 *
 * Displays job name on left, Run/Save/Close buttons on right.
 * Run and Save are disabled placeholders for future features.
 */
export function IDEHeader({
  jobName,
  onClose,
  onSave,
  onRun,
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

          <Button
            variant="secondary"
            onClick={onSave}
            disabled
            className="opacity-50"
          >
            <span
              className="hero-check size-4 inline-block mr-1"
              aria-hidden="true"
            />
            Save
          </Button>

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
