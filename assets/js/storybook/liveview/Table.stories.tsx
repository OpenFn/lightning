import type { Meta, StoryObj } from '@storybook/react-vite';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clones of `LightningWeb.Components.Table`
 * (lib/lightning_web/components/table.ex): `table/1`, `tr/1`, `th/1`, `td/1`
 * and `empty_state/1`. The "History Table" story re-creates the Work Orders
 * table from the History page (lib/lightning_web/live/run_live/index.html.heex).
 *
 * Presentational only — sorting, selection and pagination are not wired up.
 */
const TR_CLASS = cn(
  'transition-colors duration-150 has-[td]:hover:bg-gray-50 last:rounded-b-lg',
  '[&>td:first-child]:py-4 [&>td:first-child]:pr-3 [&>td:first-child]:pl-4 [&>td:first-child]:sm:pl-6',
  '[&>th:first-child]:py-3.5 [&>th:first-child]:pr-3 [&>th:first-child]:pl-4 [&>th:first-child]:sm:pl-6',
  '[&>td:not(:first-child):not(:last-child)]:px-3 [&>td:not(:first-child):not(:last-child)]:py-4',
  '[&>th:not(:first-child):not(:last-child)]:px-3 [&>th:not(:first-child):not(:last-child)]:py-3.5',
  '[&>td:last-child]:relative [&>td:last-child]:py-4 [&>td:last-child]:pr-4 [&>td:last-child]:pl-3 [&>td:last-child]:sm:pr-6',
  '[&>th:last-child]:relative [&>th:last-child]:py-3.5 [&>th:last-child]:pr-4 [&>th:last-child]:pl-3 [&>th:last-child]:sm:pr-6'
);

function Table({ children }: { children: ReactNode }) {
  return (
    <div className="bg-gray-50 shadow ring-1 ring-black/5 sm:rounded-lg">
      <table className="min-w-full divide-y divide-gray-200">{children}</table>
    </div>
  );
}

function Tr({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return <tr className={cn(TR_CLASS, className)}>{children}</tr>;
}

function Th({
  children,
  className,
  sortable,
  active,
  direction = 'asc',
}: {
  children: ReactNode;
  className?: string;
  sortable?: boolean;
  active?: boolean;
  direction?: 'asc' | 'desc';
}) {
  return (
    <th
      scope="col"
      className={cn(
        'text-left text-sm font-semibold whitespace-nowrap text-gray-900 select-none',
        className
      )}
    >
      {sortable ? (
        <button
          type="button"
          className="group inline-flex items-center gap-1 cursor-pointer"
        >
          {children}
          <span
            className={cn(
              'hero-chevron-down h-4 w-4 transition',
              active ? 'text-gray-900' : 'text-gray-300 group-hover:text-gray-400',
              active && direction === 'asc' ? 'rotate-180' : ''
            )}
          />
        </button>
      ) : (
        children
      )}
    </th>
  );
}

function Td({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <td
      className={cn(
        'text-sm text-gray-500 first:rounded-bl-lg last:rounded-br-lg',
        className
      )}
    >
      {children}
    </td>
  );
}

// --- Status pill, mirroring the Work Order run states -----------------------
type RunState =
  | 'success'
  | 'failed'
  | 'crashed'
  | 'running'
  | 'pending'
  | 'cancelled';

const STATE_PILL: Record<RunState, string> = {
  success: 'bg-green-100 text-green-700',
  failed: 'bg-red-100 text-red-700',
  crashed: 'bg-red-100 text-red-700',
  running: 'bg-blue-100 text-blue-700',
  pending: 'bg-gray-100 text-gray-600',
  cancelled: 'bg-yellow-100 text-yellow-800',
};

function StatusPill({ state }: { state: RunState }) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
        STATE_PILL[state]
      )}
    >
      {state}
    </span>
  );
}

interface WorkOrder {
  id: string;
  workflow: string;
  input: string;
  created: string;
  lastActivity: string;
  duration: string;
  state: RunState;
  runs: number;
}

const WORK_ORDERS: WorkOrder[] = [
  {
    id: 'a1b2c3d4',
    workflow: 'Patient sync',
    input: 'http_request',
    created: '2 minutes ago',
    lastActivity: '1 minute ago',
    duration: '1.2s',
    state: 'success',
    runs: 1,
  },
  {
    id: 'e5f6a7b8',
    workflow: 'DHIS2 export',
    input: 'step_result',
    created: '14 minutes ago',
    lastActivity: '12 minutes ago',
    duration: '4.8s',
    state: 'failed',
    runs: 2,
  },
  {
    id: 'c9d0e1f2',
    workflow: 'CommCare → Postgres',
    input: 'global',
    created: '1 hour ago',
    lastActivity: 'just now',
    duration: '—',
    state: 'running',
    runs: 1,
  },
  {
    id: '3a4b5c6d',
    workflow: 'Nightly aggregation',
    input: 'saved_input',
    created: '3 hours ago',
    lastActivity: '3 hours ago',
    duration: '0.0s',
    state: 'pending',
    runs: 0,
  },
  {
    id: '7e8f9a0b',
    workflow: 'Kobo intake',
    input: 'http_request',
    created: 'Yesterday',
    lastActivity: 'Yesterday',
    duration: '2.1s',
    state: 'cancelled',
    runs: 3,
  },
];

const meta = {
  title: 'LiveView Clones/Table (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const HistoryTable: Story = {
  name: 'History Table',
  render: () => (
    <Showcase className="min-w-[960px]">
      <Section
        title="Work Orders"
        description="The History page's work-orders table, built from the shared Table primitives. Created and Last Activity are sortable."
      >
        <Table>
          <thead>
            <Tr>
              <Th className="!pr-1">
                <input
                  type="checkbox"
                  aria-label="Select all work orders"
                  className="rounded border-gray-300 text-primary-600 focus:ring-primary-600"
                />
              </Th>
              <Th>ID</Th>
              <Th>Workflow</Th>
              <Th>Input</Th>
              <Th sortable active direction="desc">
                Created
              </Th>
              <Th sortable>Last Activity</Th>
              <Th className="text-right">Duration</Th>
              <Th className="text-right">Status</Th>
              <Th className="text-right">Runs</Th>
            </Tr>
          </thead>
          <tbody className="divide-y divide-gray-200 bg-white">
            {WORK_ORDERS.map(wo => (
              <Tr key={wo.id}>
                <Td className="!pr-1">
                  <input
                    type="checkbox"
                    aria-label={`Select work order ${wo.id}`}
                    className="rounded border-gray-300 text-primary-600 focus:ring-primary-600"
                  />
                </Td>
                <Td>
                  <span className="font-mono text-xs text-primary-400">
                    {wo.id}
                  </span>
                </Td>
                <Td>
                  <span className="font-medium text-gray-900">
                    {wo.workflow}
                  </span>
                </Td>
                <Td>
                  <span className="rounded-full bg-gray-100 px-2 py-0.5 font-mono text-xs text-gray-600">
                    {wo.input}
                  </span>
                </Td>
                <Td>{wo.created}</Td>
                <Td>{wo.lastActivity}</Td>
                <Td className="text-right tabular-nums">{wo.duration}</Td>
                <Td className="text-right">
                  <StatusPill state={wo.state} />
                </Td>
                <Td className="text-right tabular-nums">{wo.runs}</Td>
              </Tr>
            ))}
          </tbody>
        </Table>
      </Section>
    </Showcase>
  ),
};

export const Primitives: Story = {
  render: () => (
    <Showcase className="min-w-[560px]">
      <Section
        title="table / tr / th / td"
        description="The base table composition used across the app."
      >
        <Table>
          <thead>
            <Tr>
              <Th>Name</Th>
              <Th>Email</Th>
              <Th className="text-right">Role</Th>
            </Tr>
          </thead>
          <tbody className="divide-y divide-gray-200 bg-white">
            <Tr>
              <Td className="font-medium text-gray-900">Amara Okafor</Td>
              <Td>amara@example.org</Td>
              <Td className="text-right">Admin</Td>
            </Tr>
            <Tr>
              <Td className="font-medium text-gray-900">Wei Chen</Td>
              <Td>wei@example.org</Td>
              <Td className="text-right">Editor</Td>
            </Tr>
            <Tr>
              <Td className="font-medium text-gray-900">Sofia Rossi</Td>
              <Td>sofia@example.org</Td>
              <Td className="text-right">Viewer</Td>
            </Tr>
          </tbody>
        </Table>
      </Section>
    </Showcase>
  ),
};

export const EmptyState: Story = {
  render: () => (
    <Showcase className="min-w-[480px]">
      <Section
        title="empty_state/1 (interactive)"
        description="A dashed call-to-action shown when a collection is empty."
      >
        <button
          type="button"
          className="relative block w-full rounded-lg border-2 border-dashed border-gray-300 p-4 text-center hover:border-gray-400 focus:outline-none"
        >
          <span className="hero-plus-circle mx-auto block h-12 w-12 text-secondary-400" />
          <span className="mt-2 block text-xs font-semibold text-secondary-600">
            Create your first workflow
          </span>
          <span className="mt-2 block text-xs text-gray-500">
            Workflows move data between systems.
          </span>
        </button>
      </Section>

      <Section title="empty_state/1 (static)">
        <div className="relative block w-full rounded-lg border-2 border-dashed border-gray-300 p-4 text-center">
          <span className="hero-rectangle-stack mx-auto block h-12 w-12 text-secondary-400" />
          <span className="mt-2 block text-xs text-gray-500">
            No runs yet for this workflow.
          </span>
        </div>
      </Section>
    </Showcase>
  ),
};
