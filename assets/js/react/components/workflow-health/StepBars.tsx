import { chart, formatCount } from './theme';
import type { StepFailure, StepsWithFailures } from './types';

/**
 * The server sends structure, not copy: a null job means either "no step ran"
 * or "the job was deleted", told apart by `attributed`.
 */
const stepLabel = (step: StepFailure): string => {
  if (!step.attributed) return '(no step)';

  return step.job ?? '(deleted step)';
};

/**
 * Failures per step, as a ranked bar list.
 *
 * One series, so every bar takes the same colour — bar length already encodes
 * the magnitude, and spending a second colour channel on it would say nothing.
 * Plain markup rather than a chart component: these are labelled rows, and a
 * charting library would only make them harder to align with the counts.
 */
export const StepBars = ({ data }: { data: StepsWithFailures }) => {
  if (data.steps.length === 0) {
    return (
      <p className="py-8 text-center text-sm text-gray-400">
        No step failures in this window
      </p>
    );
  }

  const max = Math.max(...data.steps.map(step => step.count));

  return (
    <ul className="space-y-3">
      {data.steps.map(step => (
        <li key={stepLabel(step)}>
          <div className="mb-1 flex items-baseline justify-between gap-3">
            <span
              className={
                step.attributed
                  ? 'truncate font-mono text-xs text-gray-700'
                  : 'truncate font-mono text-xs italic text-gray-400'
              }
            >
              {stepLabel(step)}
            </span>
            <span className="shrink-0 text-sm font-medium tabular-nums text-gray-900">
              {formatCount(step.count)}
            </span>
          </div>
          <div
            className="h-1.5 w-full overflow-hidden rounded-full"
            style={{ backgroundColor: chart.track }}
          >
            <div
              className="h-full rounded-full"
              style={{
                width: `${(step.count / max) * 100}%`,
                backgroundColor: step.attributed
                  ? chart.stepFailures
                  : chart.axis,
              }}
            />
          </div>
        </li>
      ))}
    </ul>
  );
};
