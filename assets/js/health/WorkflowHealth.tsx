import type { ReactNode } from 'react';
import { useState } from 'react';

import { FRAME } from './charts/Donut';
import { FailureBreakdownDonut } from './charts/FailureBreakdownDonut';
import { OutcomesDonut } from './charts/OutcomesDonut';
import { TriageTable } from './charts/TriageTable';
import { DEFAULT_DAYS, RangePicker } from './RangePicker';
import type { FailureSignatures, Outcomes } from './types';
import type { Query } from './useHealthQuery';
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
  const signatures = useHealthQuery<FailureSignatures>(
    `${base}/failures?days=${days}`
  );

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-gray-900">
            {workflowName}
          </h1>
          <Subtitle outcomes={outcomes.data} loading={outcomes.loading} />
        </div>
        {/* The picker and the freshness stamp both belong to the whole page,
            so they stack in the header rather than sitting on any one card. */}
        <div className="flex shrink-0 flex-col items-end gap-1">
          <RangePicker days={days} onChange={setDays} />
          <UpdatedAt at={outcomes.fetchedAt} />
        </div>
      </div>

      <div className="grid gap-6 md:grid-cols-2">
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

        {/* Same reply as the panel beside it — one aggregate read two ways, so
            the wedge here and the red wedge there cannot disagree. */}
        <Card title="Failure breakdown" meta="by work order state">
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

      <Card title="Triage" meta="grouped by failure type">
        <Panel data={signatures.data} error={signatures.error}>
          {({ signatures, window }) => (
            <TriageTable
              signatures={signatures}
              emptyMessage={emptyMessage(window, 'failures')}
            />
          )}
        </Panel>
      </Card>
    </div>
  );
};

const Card = ({
  title,
  meta,
  children,
}: {
  title: string;
  meta: ReactNode;
  children: ReactNode;
}) => (
  <div className="rounded-lg bg-white p-6 shadow">
    <div className="mb-4 flex items-baseline justify-between gap-4">
      <h2 className="text-sm font-medium text-gray-900">{title}</h2>
      {meta && <span className="text-xs text-gray-500">{meta}</span>}
    </div>
    {children}
  </div>
);

// Each card owns its own failure, so one bad request can't take the rest of
// the page with it. A `health:changed` refetch keeps the numbers it already
// has; a range switch drops them, since they answer the old window.
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
  // where the polite subtitle would only fall silent.
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
// region: the subtitle announces loading once for the page, this text is only
// for a reader who lands inside the card.
const ChartLoading = () => (
  <div className={FRAME}>
    <span className="sr-only">Loading…</span>
  </div>
);

// The page runs no timer of its own: this clock moves only when the server says
// one of the workflow's work orders settled. A time that has just jumped is the
// page showing that updates are still reaching it.
const UpdatedAt = ({ at }: { at: Query<Outcomes>['fetchedAt'] }) => {
  if (!at) return null;

  return (
    <span className="text-xs text-gray-500">
      Last Updated {at.toLocaleTimeString()}
    </span>
  );
};

// Holds its line while empty (`min-h-5` is one `text-sm` line). It names the
// window the numbers beside it came from, and goes back to "Loading…" on a
// range switch rather than naming a window no panel is showing yet. The page's
// one polite live region: a first load and a range switch are each read out
// here once, rather than by every card in turn.
const Subtitle = ({
  outcomes,
  loading,
}: {
  outcomes: Outcomes | null;
  loading: boolean;
}) => (
  <p role="status" className="min-h-5 text-sm text-gray-500">
    {outcomes
      ? `Last ${windowLabel(outcomes.window)} · ${workOrders(outcomes.counts)}`
      : loading && 'Loading…'}
  </p>
);

// "1 work order", "1,287 work orders": the subtitle and the Outcomes card both
// say it, so it is spelled once.
const workOrders = (counts: Outcomes['counts']) => {
  const total = Object.values(counts).reduce((sum, count) => sum + count, 0);

  return `${total.toLocaleString()} work order${total === 1 ? '' : 's'}`;
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
