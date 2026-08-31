import { SocketProvider } from '#/react/contexts/SocketProvider';

import { OutcomesDonut } from './charts/OutcomesDonut';
import { useHealthStats } from './useHealthStats';

/**
 * Workflow health page: a 30-day summary of one workflow's work orders.
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
  <SocketProvider>
    <HealthContent
      workflowId={props['data-workflow-id']}
      projectId={props['data-project-id']}
      workflowName={props['data-workflow-name']}
    />
  </SocketProvider>
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
  const { outcomes, error } = useHealthStats(workflowId, projectId);

  if (error) {
    return <p className="text-sm text-red-700">{error}</p>;
  }

  if (!outcomes) {
    return <p className="text-sm text-gray-500">Loading…</p>;
  }

  const days = windowDays(outcomes.window);
  const total = Object.values(outcomes.counts).reduce((a, b) => a + b, 0);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-semibold text-gray-900">{workflowName}</h1>
        <p className="text-sm text-gray-500">
          Last {days} days · {total.toLocaleString()} work orders
        </p>
      </div>

      <div className="rounded-lg bg-white p-6 shadow">
        <h2 className="mb-4 text-sm font-medium text-gray-900">Outcomes</h2>
        <OutcomesDonut
          counts={outcomes.counts}
          emptyMessage={`No completed work orders in the last ${days} days`}
        />
      </div>
    </div>
  );
};

const windowDays = ({ from, to }: { from: string; to: string }) =>
  Math.round((Date.parse(to) - Date.parse(from)) / 86_400_000);
