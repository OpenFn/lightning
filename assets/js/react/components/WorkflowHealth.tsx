import { Donut } from './workflow-health/Donut';
import { LegendRow, Panel } from './workflow-health/Panel';
import { ResponseTimeChart } from './workflow-health/ResponseTimeChart';
import { StepBars } from './workflow-health/StepBars';
import {
  chart,
  failureKindColor,
  formatCount,
  formatDuration,
} from './workflow-health/theme';
import { TriageTable } from './workflow-health/TriageTable';
import type { WorkflowHealthProps } from './workflow-health/types';
import { VolumeChart } from './workflow-health/VolumeChart';

/**
 * The workflow health screen.
 *
 * Every panel here is computed from data Lightning already stores. The parts
 * that are not — error messages, and therefore true error signatures, plus the
 * triage row actions — are marked in place rather than left to look finished.
 */
export const WorkflowHealth = ({
  outcomes,
  failure_breakdown,
  steps_with_failures,
  volume_over_time,
  response_time,
  triage,
}: WorkflowHealthProps) => (
  <div className="space-y-4">
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
      <Panel title="Outcomes" meta={`${formatCount(outcomes.total)} runs`}>
        <Donut
          centerValue={`${outcomes.success_rate.toFixed(0)}%`}
          centerLabel="success"
          slices={[
            {
              key: 'success',
              label: 'success',
              value: outcomes.success,
              color: chart.success,
            },
            {
              key: 'failed',
              label: 'failed',
              value: outcomes.failed,
              color: chart.failure,
            },
          ]}
        />
        <ul className="mt-4 space-y-1.5">
          <LegendRow
            color={chart.success}
            label="success"
            count={outcomes.success}
            percentage={outcomes.success_rate}
          />
          <LegendRow
            color={chart.failure}
            label="failed"
            count={outcomes.failed}
            percentage={outcomes.failure_rate}
          />
        </ul>
      </Panel>

      <Panel title="Failure breakdown" meta="by run state">
        <Donut
          centerValue={formatCount(failure_breakdown.total)}
          centerLabel="failures"
          slices={failure_breakdown.reasons.map(reason => ({
            key: reason.state,
            label: reason.state,
            value: reason.count,
            color: failureKindColor(reason.state),
          }))}
        />
        <ul className="mt-4 space-y-1.5">
          {failure_breakdown.reasons.map(reason => (
            <LegendRow
              key={reason.state}
              color={failureKindColor(reason.state)}
              label={reason.state}
              count={reason.count}
              percentage={reason.percentage}
            />
          ))}
        </ul>
      </Panel>

      <Panel
        title="Steps with failures"
        meta={`${formatCount(steps_with_failures.total)} total`}
        footnote={
          steps_with_failures.unattributed > 0 ? (
            <>
              {formatCount(steps_with_failures.unattributed)} failures happened
              before any step ran, so they cannot be attributed to a job.
            </>
          ) : null
        }
      >
        <StepBars data={steps_with_failures} />
      </Panel>
    </div>

    <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
      <Panel
        title="Volume over time"
        meta={bucketLabel(volume_over_time.bucket_seconds)}
        footnote={
          <span className="flex items-center gap-4">
            <Swatch color={chart.runs} label="Succeeded" />
            <Swatch color={chart.runsFailed} label="Failed" />
          </span>
        }
      >
        <VolumeChart data={volume_over_time} />
      </Panel>

      <Panel
        title="Response time"
        meta={
          <span className="flex gap-4 tabular-nums">
            <Stat label="P50" value={formatDuration(response_time.p50)} />
            <Stat label="P95" value={formatDuration(response_time.p95)} />
            <Stat label="Max" value={formatDuration(response_time.max)} />
          </span>
        }
        footnote={`Across ${formatCount(response_time.sampled)} finished runs.`}
      >
        <ResponseTimeChart data={response_time} />
      </Panel>
    </div>

    <section>
      <h2 className="mb-3 text-xs font-semibold uppercase tracking-wide text-gray-500">
        Triage — grouped by failure type
      </h2>
      <TriageTable rows={triage} />
    </section>
  </div>
);

const Stat = ({ label, value }: { label: string; value: string }) => (
  <span className="flex flex-col items-end leading-tight">
    <span className="text-[10px] uppercase tracking-wide text-gray-400">
      {label}
    </span>
    <span className="text-sm font-semibold text-gray-900">{value}</span>
  </span>
);

const Swatch = ({ color, label }: { color: string; label: string }) => (
  <span className="flex items-center gap-1.5">
    <span
      aria-hidden="true"
      className="size-2.5 rounded-[2px]"
      style={{ backgroundColor: color }}
    />
    {label}
  </span>
);

const bucketLabel = (seconds: number): string => {
  if (seconds >= 86_400) return `${seconds / 86_400}-day buckets`;
  if (seconds >= 3600) return `${seconds / 3600}-hour buckets`;
  return `${seconds / 60}-minute buckets`;
};
