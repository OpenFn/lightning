import { cn } from '#/utils/cn';

import type { ErrorSignature } from '../types';

import { EMPTY } from './Donut';
import { FAILED } from './OutcomesDonut';

/**
 * Which steps the window's failures land on, heaviest first, as a bar per step.
 *
 * Derived from the same `failures` response the triage table draws, folded
 * down to the step: triage answers "what broke", this answers "where". No
 * second request, and the two cannot disagree about a step's weight.
 *
 * Work orders, not steps — a count is how many failed work orders hold a
 * failing step of that job, which is `error_signatures/2`'s unit. A work order
 * that broke in two branches is counted under each, so the rows can sum past
 * the failure total the donuts draw; that second branch is its own thing to
 * fix.
 *
 * Bars are shares of the heaviest row, not of the total: the question is which
 * step to look at first, and against a total every row on a workflow with ten
 * failing steps is a sliver.
 *
 * No link per row. History's error-signature filter is switched on by
 * `exit_reason` (`Lightning.Invocation.filter_by_error_signature/2`) and a
 * step on its own doesn't carry one, so a row here has no filter to land on —
 * the triage table below is where a specific failure is opened.
 */

// Grey, where every other row is the failure red: these are the work orders
// there is no step to blame, so the row reads as "unattributed" rather than as
// one more step to go and look at. Not `CANCELLED`'s grey by reference — that
// one means "stopped on purpose", and sharing the constant would tie two
// unrelated meanings to one value.
const UNATTRIBUTED = 'var(--color-gray-400)';

const NO_STEP = 'no-step';

interface StepFailureBarsProps {
  signatures: ErrorSignature[];
  emptyMessage: string;
}

export const StepFailureBars = ({
  signatures,
  emptyMessage,
}: StepFailureBarsProps) => {
  const rows = groupByStep(signatures);

  if (rows.length === 0) {
    return <p className={EMPTY}>{emptyMessage}</p>;
  }

  const max = Math.max(...rows.map(({ count }) => count));
  const unattributed = rows.find(({ key }) => key === NO_STEP)?.count ?? 0;

  return (
    <div className="flex flex-col gap-4">
      {/* Capped and scrolled rather than truncated to a top few, the same way
          the triage table is: the tail is still worth reading, just not worth
          growing the card for. `-mr-6 pr-4` puts the scrollbar flush against
          the card's edge, past its `p-6`, and `relative` keeps anything
          `sr-only` added to a row from escaping the clip — see the same note
          on `TriageTable`. */}
      <ul className="relative -mr-6 flex max-h-64 flex-col gap-3 overflow-y-auto pr-4">
        {rows.map(({ key, label, count }) => (
          <li key={key} className="flex flex-col gap-1">
            <div className="flex items-baseline justify-between gap-4 text-sm">
              {/* Monospace, matching the triage table's signatures — a step
                  name is a job's identifier, not prose. Italic for the
                  unattributed row, which names a bucket rather than a job. */}
              <span
                className={cn(
                  'min-w-0 truncate',
                  key === NO_STEP
                    ? 'italic text-gray-500'
                    : 'font-mono text-gray-900'
                )}
                title={label}
              >
                {label}
              </span>
              <span className="shrink-0 font-semibold tabular-nums text-gray-900">
                {count.toLocaleString()}
              </span>
            </div>
            {/* The count beside it is the accessible value; the bar only
                ranks the rows against each other. */}
            <div aria-hidden="true" className="h-1.5 rounded-full bg-gray-100">
              <div
                className="h-1.5 rounded-full"
                style={{
                  width: `${(count / max) * 100}%`,
                  backgroundColor: key === NO_STEP ? UNATTRIBUTED : FAILED,
                }}
              />
            </div>
          </li>
        ))}
      </ul>

      {unattributed > 0 && (
        <p className="text-sm text-gray-500">
          {unattributed.toLocaleString()}{' '}
          {unattributed === 1 ? 'failure has' : 'failures have'} no failing
          step, so there is no job to attribute{' '}
          {unattributed === 1 ? 'it' : 'them'} to.
        </p>
      )}
    </div>
  );
};

/**
 * One row per job, plus one for the work orders with no failing step to blame
 * — a rejected work order, or a run lost or crashed without a step reporting.
 *
 * Signatures split a job by exit reason and error type; this folds those back
 * together, because a step is one place to go and look however many ways it
 * broke. Safe to sum: within a run a job runs at most once, so no work order
 * is in two signatures for the same job.
 */
const groupByStep = (signatures: ErrorSignature[]) => {
  const rows = new Map<string, { key: string; label: string; count: number }>();

  for (const { job_id, step_name, count } of signatures) {
    const key = job_id ?? NO_STEP;
    const existing = rows.get(key);

    if (existing) {
      existing.count += count;
    } else {
      // A job with no name resolved off any snapshot in the window — it should
      // not happen, but it must not render as a blank row either.
      const label = job_id ? step_name || '(unknown step)' : '(no step)';
      rows.set(key, { key, label, count });
    }
  }

  return [...rows.values()].sort(
    (a, b) => b.count - a.count || a.label.localeCompare(b.label)
  );
};

/** "141 total", for the card's meta. */
export const stepFailureTotal = (signatures: ErrorSignature[]) =>
  `${signatures.reduce((sum, { count }) => sum + count, 0).toLocaleString()} total`;
