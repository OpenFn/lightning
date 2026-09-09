import type { ReactNode } from 'react';
import { useState } from 'react';

import { cn } from '#/utils/cn';

import { FRAME } from './charts/Donut';
import { FailureBreakdownDonut } from './charts/FailureBreakdownDonut';
import { OutcomesDonut } from './charts/OutcomesDonut';
import { TriageTable } from './charts/TriageTable';
import type { RunVolume } from './charts/VolumeBars';
import { bucketMeta, VolumeBars } from './charts/VolumeBars';
import { DEFAULT_DAYS, RangePicker } from './RangePicker';
import type { ErrorSignatures, Outcomes } from './types';
import { FAILURE_STATES } from './types';
import { healthBase, useHealthQuery } from './useHealthQuery';

/**
 * Workflow health page: one workflow's work orders over the window the reader
 * picks, defaulting to the last 30 days.
 *
 * Work orders, not runs — the page exists to drive failures down, and only a
 * work order's state can fall. A run's state is immutable, so a retried
 * failure would sit here permanently; retry the work order and this page's
 * numbers actually move.
 *
 * Mounted via `phx-hook="ReactComponent"`, so props arrive as the element's
 * raw kebab-case `data-*` attributes and are always strings.
 */

interface WorkflowHealthProps {
  'data-workflow-id': string;
  'data-project-id': string;
  'data-workflow-name': string;
}

// Keyed on the workflow: a patch between two workflows' health pages remounts
// everything, the picked range included, rather than leaving one workflow's
// page state under another's heading.
export const WorkflowHealth = (props: WorkflowHealthProps) => (
  <HealthContent
    key={props['data-workflow-id']}
    workflowId={props['data-workflow-id']}
    projectId={props['data-project-id']}
    workflowName={props['data-workflow-name']}
  />
);

interface HealthContentProps {
  workflowId: string;
  projectId: string;
  workflowName: string;
}

export const HealthContent = ({
  workflowId,
  projectId,
  workflowName,
}: HealthContentProps) => {
  const [days, setDays] = useState<string>(DEFAULT_DAYS);

  const base = healthBase(projectId, workflowId);

  const outcomes = useHealthQuery<Outcomes>(`${base}/outcomes?days=${days}`);
  const signatures = useHealthQuery<ErrorSignatures>(
    `${base}/failures?days=${days}`
  );
  // Counts runs where the rest of the page counts work orders, so there is
  // nothing to share with the other two queries.
  const volume = useHealthQuery<RunVolume>(`${base}/runs?days=${days}`);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-start justify-between gap-4">
        <h1 className="min-w-0 text-2xl font-semibold break-words text-gray-900">
          {workflowName}
        </h1>
        {/* The picker and the freshness stamp both belong to the whole page,
            so they stack in the header rather than sitting on any one card. */}
        <div className="flex shrink-0 flex-col items-end gap-1">
          <RangePicker days={days} onChange={setDays} />
          <UpdatedAt at={outcomes.data?.window.to ?? null} />
        </div>
      </div>

      {/* Four columns: a narrow donut beside a wide time axis, then an even
          split. Stacks in source order below `lg`. */}
      <div className="grid gap-6 lg:grid-cols-4">
        <Card
          title="Outcomes"
          meta={outcomes.data && workOrders(outcomes.data.counts)}
        >
          <Panel data={outcomes.data} error={outcomes.error}>
            {({ counts, window }) => (
              <OutcomesDonut
                counts={counts}
                emptyMessage={emptyMessage(window)}
              />
            )}
          </Panel>
        </Card>

        {/* Runs, where the donut beside it counts work orders — so the meta
            names the bucket size rather than a total that won't reconcile. */}
        <Card
          title="Volume over time"
          className="lg:col-span-3"
          meta={volume.data && bucketMeta(volume.data.buckets)}
        >
          <Panel data={volume.data} error={volume.error}>
            {({ buckets, window }) => (
              <VolumeBars
                buckets={buckets}
                emptyMessage={emptyMessage(window, 'runs')}
              />
            )}
          </Panel>
        </Card>

        {/* Counts are per failed step, so the rows can sum past the failure
            total the donuts draw: a second broken branch is its own thing to
            fix. */}
        <Card
          title="Triage"
          className="lg:col-span-2"
          meta="grouped by failure type · counted once per failed branch"
        >
          <Panel data={signatures.data} error={signatures.error}>
            {({ signatures, window }) => (
              <TriageTable
                signatures={signatures}
                emptyMessage={emptyMessage(window, 'failures')}
                projectId={projectId}
                workflowId={workflowId}
                from={window.from}
              />
            )}
          </Panel>
        </Card>

        {/* Same reply as the Outcomes panel — one aggregate read two ways, so
            the slices here and the red wedge there cannot disagree. */}
        <Card
          title="Failure breakdown"
          className="lg:col-span-2"
          meta={
            outcomes.data &&
            `${failures(outcomes.data.counts)} · by work order state`
          }
        >
          <Panel data={outcomes.data} error={outcomes.error}>
            {({ counts, window }) => (
              <FailureBreakdownDonut
                counts={counts}
                emptyMessage={emptyMessage(window, 'failures')}
              />
            )}
          </Panel>
        </Card>
      </div>
    </div>
  );
};

const Card = ({
  title,
  meta,
  className,
  children,
}: {
  title: string;
  meta: ReactNode;
  className?: string;
  children: ReactNode;
}) => (
  // A column, so a panel that wants the room can take the height the grid row
  // stretches this card to instead of leaving it blank.
  <div
    className={cn('flex flex-col rounded-lg bg-white p-6 shadow', className)}
  >
    <div className="mb-4 flex items-baseline justify-between gap-4">
      <h2 className="text-sm font-medium text-gray-900">{title}</h2>
      {meta && <span className="text-xs text-gray-500">{meta}</span>}
    </div>
    {children}
  </div>
);

// Each card owns its own failure, so one bad request can't take the rest of
// the page with it. A poll keeps the numbers it already has; a range switch
// drops them, since they answer the old window.
const Panel = <T,>({
  data,
  error,
  children,
}: {
  data: T | null;
  error: string | null;
  children: (data: T) => ReactNode;
}) => {
  // `alert` is the assertive live region: a failure is read out at once,
  // where the polite stamp above would only fall silent.
  if (error) {
    return (
      <p role="alert" className="text-sm text-red-700">
        {error}
      </p>
    );
  }
  if (!data) return <ChartLoading />;

  return children(data);
};

// Reached on a first load and again after a failure, so it holds the chart's
// frame either way and the card doesn't jump when the data lands. Not a live
// region: this text is only for a reader who lands inside the card.
const ChartLoading = () => (
  <div className={FRAME}>
    <span className="sr-only">Loading…</span>
  </div>
);

// The stamp is the server's compute time, not the moment the browser asked —
// `window.to` is when the numbers were true, however long the round trip took.
//
// Holds its line while empty (`min-h-4` is one `text-xs` line) so the picker
// above it doesn't move.
const UpdatedAt = ({ at }: { at: string | null }) => (
  <p className="min-h-4 text-xs text-gray-500">
    {at && `Last Updated ${new Date(at).toLocaleTimeString()}`}
  </p>
);

// "1 work order", "1,287 work orders".
const workOrders = (counts: Outcomes['counts']) => {
  const total = Object.values(counts).reduce((sum, count) => sum + count, 0);

  return `${total.toLocaleString()} work order${total === 1 ? '' : 's'}`;
};

// The donut's centre total sits inside the `aria-hidden` frame and the legend
// below lists slices but never their sum, so this is the only place a screen
// reader can reach the number of failures. Summed from `FAILURE_STATES` rather
// than the drawn slices, which drop the states that never happened.
const failures = (counts: Outcomes['counts']) => {
  const total = FAILURE_STATES.reduce((sum, state) => sum + counts[state], 0);

  return `${total.toLocaleString()} failure${total === 1 ? '' : 's'}`;
};

const emptyMessage = (
  window: Outcomes['window'],
  noun = 'finished work orders'
) => `No ${noun} in the last ${windowLabel(window)}`;

const windowDays = ({ from, to }: { from: string; to: string }) =>
  Math.round((Date.parse(to) - Date.parse(from)) / 86_400_000);

// Matches the picker's own wording — "24 hours", not "1 day".
const windowLabel = (window: Outcomes['window']) => {
  const days = windowDays(window);

  return days === 1 ? '24 hours' : `${days} days`;
};
