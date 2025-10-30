import { useURLState } from "../../../react/lib/use-url-state";
import type { Step } from "../../types/run";
import { ElapsedIndicator } from "./ElapsedIndicator";
import { StepIcon } from "./StepIcon";

interface StepItemProps {
  step: Step;
  selected: boolean;
  onSelect: () => void;
}

export function StepItem({ step, selected, onSelect }: StepItemProps) {
  const { searchParams, updateSearchParams } = useURLState();

  const handleInspect = (e: React.MouseEvent) => {
    e.stopPropagation();

    // Get current run ID from URL to preserve context
    const currentRunId = searchParams.get("run");

    // Update URL to switch job but preserve run/step context
    updateSearchParams({
      job: step.job_id,
      run: currentRunId, // Preserve run context
      step: step.id, // Update to this step
    });
  };

  return (
    <div
      onClick={onSelect}
      className={`
        relative flex items-center space-x-3 p-2 rounded
        cursor-pointer border-r-4 transition-colors
        ${
          selected
            ? "border-primary-500 bg-primary-50 font-semibold"
            : "border-transparent hover:border-gray-300 hover:bg-gray-50"
        }
      `}
    >
      <StepIcon exitReason={step.exit_reason} errorType={step.error_type} />

      <div className="flex-1 min-w-0 flex items-center space-x-2">
        <span className="text-sm truncate">
          {step.job?.name || "Unknown Job"}
        </span>

        <button
          onClick={handleInspect}
          className="flex-shrink-0 text-gray-400 hover:text-primary-600"
          title="Inspect Step"
          aria-label={`Inspect step ${step.job?.name || "Unknown Job"}`}
        >
          <span
            className="hero-document-magnifying-glass-mini size-5"
            aria-hidden="true"
          />
        </button>
      </div>

      <div className="flex-shrink-0 text-xs text-gray-500">
        <ElapsedIndicator
          startedAt={step.started_at}
          finishedAt={step.finished_at}
        />
      </div>
    </div>
  );
}
