import { Tab, TabGroup, TabList, TabPanel, TabPanels } from '@headlessui/react';
import type { ReactNode } from 'react';
import { useState } from 'react';

import { cn } from '#/utils/cn';

import { FRAME } from './charts/Donut';
import { FailureBreakdownDonut } from './charts/FailureBreakdownDonut';
import { OutcomesDonut } from './charts/OutcomesDonut';
import { StepFailureBars, stepFailureTotal } from './charts/StepFailureBars';
import { TriageTable } from './charts/TriageTable';
import type { RunVolume } from './charts/VolumeBars';
import { bucketMeta, VolumeBars } from './charts/VolumeBars';
import { DEFAULT_DAYS, RangePicker } from './RangePicker';
import type { ErrorSignatures, Outcomes } from './types';
import { failureTotal } from './types';
import { healthBase, useHealthQuery } from './useHealthQuery';

/**
 * Workflow health page: one workflow's work orders over the window the reader
 * picks.
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
  'data-history-retention-period'?: string;
}

export const WorkflowHealth = ({
  'data-workflow-id': workflowId,
  'data-project-id': projectId,
  'data-workflow-name': workflowName,
  'data-history-retention-period': historyRetentionPeriod,
}: WorkflowHealthProps) => {
  const [days, setDays] = useState<string>(DEFAULT_DAYS);

  const retentionDays = historyRetentionPeriod
    ? Number(historyRetentionPeriod)
    : null;

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
        {/* The picker sets the window for every card, so it belongs to the
            header rather than to any one of them. */}
        <div className="shrink-0">
          <RangePicker
            days={days}
            onChange={setDays}
            retentionDays={retentionDays}
          />
        </div>
      </div>

      {/* The tabs swap the top row between what the work orders came to and
          how many runs it took. Both queries keep polling whichever tab is
          open, so switching never waits on a load. */}
      <TabGroup className="flex flex-col gap-6">
        <TabList
          aria-label="Count by"
          className="tabbed-selector flex space-x-4"
        >
          {['Work orders', 'Runs'].map(label => (
            <Tab
              key={label}
              className="!font-medium focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:rounded-md focus-visible:outline-primary-600 data-selected:!border-b-primary-600"
            >
              {label}
            </Tab>
          ))}
        </TabList>

        <TabPanels>
          {/* One card wide by default, three across at `lg`. The cards stretch
              to the row's height so the band reads as one. */}
          <TabPanel className="grid gap-6 lg:grid-cols-3">
            <Card
              title="Outcomes"
              meta={outcomes.data && workOrders(outcomes.data.counts)}
            >
              <Panel data={outcomes.data} error={outcomes.error}>
                {({ counts, window }) => (
                  <OutcomesDonut
                    counts={counts}
                    emptyMessage={emptyMessage(window)}
                    projectId={projectId}
                    workflowId={workflowId}
                    from={window.from}
                  />
                )}
              </Panel>
            </Card>

            {/* Same reply as the Outcomes panel — one aggregate read two ways,
                so the slices here and the red wedge there cannot disagree. */}
            <Card
              title="Failure breakdown"
              meta={outcomes.data && failures(outcomes.data.counts)}
            >
              <Panel data={outcomes.data} error={outcomes.error}>
                {({ counts, window }) => (
                  <FailureBreakdownDonut
                    counts={counts}
                    emptyMessage={emptyMessage(window, 'failures')}
                    projectId={projectId}
                    workflowId={workflowId}
                    from={window.from}
                  />
                )}
              </Panel>
            </Card>

            {/* The same `failures` reply as Triage, folded from "what broke"
                down to "where" — so it costs no request, and the two cannot
                disagree about a step's weight. */}
            <Card
              title="Steps with failures"
              meta={
                signatures.data && stepFailureTotal(signatures.data.signatures)
              }
            >
              <Panel data={signatures.data} error={signatures.error}>
                {({ signatures, window }) => (
                  <StepFailureBars
                    signatures={signatures}
                    emptyMessage={emptyMessage(window, 'failures')}
                  />
                )}
              </Panel>
            </Card>
          </TabPanel>

          {/* Runs, where the other tab counts work orders — so the meta names
              the bucket size rather than a total that won't reconcile. */}
          <TabPanel>
            <Card
              title="Runs over time"
              meta={volume.data && bucketMeta(volume.data)}
            >
              <Panel data={volume.data} error={volume.error}>
                {({ buckets, window, timezone, bucket_hours }) => (
                  <VolumeBars
                    buckets={buckets}
                    timezone={timezone}
                    hours={bucket_hours}
                    emptyMessage={emptyMessage(window, 'runs')}
                    projectId={projectId}
                    workflowId={workflowId}
                  />
                )}
              </Panel>
            </Card>
          </TabPanel>
        </TabPanels>
      </TabGroup>

      {/* Titled above the card rather than inside it, so the table's header
          band is the top of the card. The card padding is for the loading,
          empty and error states; the table itself runs to the edges. */}
      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-medium tracking-wide text-gray-500 uppercase">
          Triage - grouped by failure type
        </h2>
        <div className="flex flex-col rounded-lg bg-white p-6 shadow">
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
        </div>
      </section>
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
  meta?: ReactNode;
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

// "1 work order", "1,287 failed work orders".
const count = (n: number, noun: string) =>
  `${n.toLocaleString()} ${noun}${n === 1 ? '' : 's'}`;

const workOrders = (counts: Outcomes['counts']) =>
  count(
    Object.values(counts).reduce((sum, n) => sum + n, 0),
    'work order'
  );

// The donut's centre total sits inside the `aria-hidden` frame and the legend
// below lists slices but never their sum, so this is the only place a screen
// reader can reach the number of failures. Summed from `FAILURE_STATES` rather
// than the drawn slices, which drop the states that never happened.
const failures = (counts: Outcomes['counts']) =>
  count(failureTotal(counts), 'failed work order');

const emptyMessage = (
  window: Outcomes['window'],
  noun = 'finished work orders'
) => `No ${noun} in the last ${windowLabel(window)}`;

// The runs window ends with the bucket `now` sits in, so it is `days` plus a
// part-bucket. Floor it, or a 30-day view reads as "31 days" after midday.
const windowDays = ({ from, to }: { from: string; to: string }) =>
  Math.floor((Date.parse(to) - Date.parse(from)) / 86_400_000);

// Matches the picker's own wording — "24 hours", not "1 day".
const windowLabel = (window: Outcomes['window']) => {
  const days = windowDays(window);

  return days === 1 ? '24 hours' : `${days} days`;
};
