import type { ReactNode } from 'react';

import { FailureBreakdownDonut } from './charts/FailureBreakdownDonut';
import { OutcomesDonut } from './charts/OutcomesDonut';
import { TriageTable } from './charts/TriageTable';
import type { FailureSignatures, Outcomes } from './types';
import { healthBase, useHealthQuery } from './useHealthQuery';

/**
 * Workflow health page: a 30-day summary of one workflow's runs.
 *
 * Runs, not work orders — a retry is its own attempt with its own outcome, and
 * the failure breakdown can only name a state that belongs to an attempt.
 *
 * Mounted via `phx-hook="ReactComponent"`, so props arrive as the element's
 * raw kebab-case `data-*` attributes and are always strings.
 */

interface WorkflowHealthProps {
  'data-workflow-id': string;
  'data-project-id': string;
  'data-workflow-name': string;
}

export const WorkflowHealth = (props: WorkflowHealthProps) => (
  <HealthContent
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
  const base = healthBase(projectId, workflowId);

  const outcomes = useHealthQuery<Outcomes>(`${base}/outcomes`);
  const signatures = useHealthQuery<FailureSignatures>(`${base}/failures`);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-semibold text-gray-900">{workflowName}</h1>
        <Subtitle outcomes={outcomes.data} />
      </div>

      <div className="grid gap-6 md:grid-cols-2">
        <Card
          title="Outcomes"
          meta={
            outcomes.data &&
            `${runTotal(outcomes.data.counts).toLocaleString()} runs`
          }
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
        <Card title="Failure breakdown" meta="by run state">
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

// Each card owns its own loading and failure, so one slow or broken request
// can't take the rest of the page with it.
const Panel = <T,>({
  data,
  error,
  children,
}: {
  data: T | null;
  error: string | null;
  children: (data: T) => ReactNode;
}) => {
  if (error) return <p className="text-sm text-red-700">{error}</p>;
  if (!data) return <p className="text-sm text-gray-500">Loading…</p>;

  return children(data);
};

const Subtitle = ({ outcomes }: { outcomes: Outcomes | null }) => {
  if (!outcomes) return null;

  const days = windowDays(outcomes.window);
  const total = runTotal(outcomes.counts);

  return (
    <p className="text-sm text-gray-500">
      Last {days} day{days === 1 ? '' : 's'} · {total.toLocaleString()} run
      {total === 1 ? '' : 's'}
    </p>
  );
};

const runTotal = (counts: Outcomes['counts']) =>
  Object.values(counts).reduce((sum, count) => sum + count, 0);

const emptyMessage = (window: Outcomes['window'], noun = 'finished runs') => {
  const days = windowDays(window);

  return `No ${noun} in the last ${days} day${days === 1 ? '' : 's'}`;
};

const windowDays = ({ from, to }: { from: string; to: string }) =>
  Math.round((Date.parse(to) - Date.parse(from)) / 86_400_000);
