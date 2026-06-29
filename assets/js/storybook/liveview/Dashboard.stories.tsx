import type { Meta, StoryObj } from '@storybook/react-vite';
import { useState } from 'react';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clones of the project-dashboard components in
 * `LightningWeb.WorkflowLive.DashboardComponents`
 * (lib/lightning_web/live/workflow_live/dashboard_components.ex):
 * `workflow_card/1`, `create_workflow_card/1`, `search_workflows_input/1`,
 * `state_card/1`, `status_card/1`, `project_metrics/1`, `metric_card/1` and a
 * `workflow_list`-style table; plus `welcome_banner/1` from
 * `LightningWeb.DashboardLive.Components`
 * (lib/lightning_web/live/dashboard_live/components.ex).
 *
 * Presentational only — navigation, sorting, the `phx-keyup` search and the
 * `toggle_workflow_state` event are replaced with local state or omitted. The
 * `<.button>`/`<.input type="toggle">`/`Common.datetime` server components are
 * inlined as plain markup with their original Tailwind classes.
 */

// --- shared run-state metadata, mirroring status_card/1 ---------------------
type WorkOrderState =
  | 'pending'
  | 'running'
  | 'success'
  | 'failed'
  | 'crashed'
  | 'cancelled'
  | 'killed'
  | 'exception'
  | 'lost';

const ACTIVE_STATES: WorkOrderState[] = ['pending', 'running'];

const DOT_COLOR: Record<WorkOrderState, string> = {
  pending: 'bg-gray-600',
  running: 'bg-blue-600',
  success: 'bg-green-600',
  failed: 'bg-red-600',
  crashed: 'bg-orange-600',
  cancelled: 'bg-gray-500',
  killed: 'bg-yellow-600',
  exception: 'bg-gray-300 border-solid border-2 border-gray-800',
  lost: 'bg-gray-300 border-solid border-2 border-gray-800',
};

const FONT_COLOR: Record<WorkOrderState, string> = {
  pending: 'text-gray-500',
  running: 'text-blue-500',
  success: 'text-green-500',
  failed: 'text-red-500',
  crashed: 'text-orange-500',
  cancelled: 'text-gray-500',
  killed: 'text-yellow-800',
  exception: 'text-gray-600',
  lost: 'text-gray-600',
};

// Mirrors RunLive.Components.display_text_from_state/1 for work-order states.
const STATE_TEXT: Record<WorkOrderState, string> = {
  pending: 'Enqueued',
  running: 'Running',
  success: 'Success',
  failed: 'Failed',
  crashed: 'Crashed',
  cancelled: 'Cancelled',
  killed: 'Killed',
  exception: 'Exception',
  lost: 'Lost',
};

// Common.datetime renders a formatted, tooltip-bearing <time>; here it is just
// a string fixture.
function DateTime({ value }: { value: string }) {
  return <time>{value}</time>;
}

// --- workflow_card/1 --------------------------------------------------------
interface WorkflowCardData {
  id: string;
  name: string;
  updatedAt: string;
  triggerEnabled: boolean;
}

function WorkflowCard({ workflow }: { workflow: WorkflowCardData }) {
  return (
    <div className="flex flex-1 items-center truncate">
      <div className="text-sm">
        <div className="flex items-center">
          <span
            className={cn(
              'flex-shrink truncate font-medium workflow-name',
              workflow.triggerEnabled ? 'text-gray-900' : 'text-gray-400'
            )}
            style={{
              maxWidth: '200px',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
            }}
          >
            {workflow.name}
          </span>
        </div>
        <p className="text-gray-500 text-xs mt-1">
          Updated <DateTime value={workflow.updatedAt} />
        </p>
      </div>
    </div>
  );
}

// --- create_workflow_card/1 (renders NewInputs.button/1, theme="primary") ---
function CreateWorkflowCard({ disabled = false }: { disabled?: boolean }) {
  return (
    <div>
      <button
        type="button"
        disabled={disabled}
        id="new-workflow-button"
        className={cn(
          'rounded-md text-sm font-semibold shadow-xs cursor-pointer disabled:cursor-auto',
          'px-3 py-2',
          disabled
            ? 'bg-primary-300 text-white'
            : 'bg-primary-600 hover:bg-primary-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600',
          'col-span-1 w-full'
        )}
      >
        Create new workflow
      </button>
    </div>
  );
}

// --- search_workflows_input/1 -----------------------------------------------
function SearchWorkflowsInput() {
  const [term, setTerm] = useState('');
  return (
    <div className="relative rounded-md shadow-xs flex h-full">
      <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
        <span className="hero-magnifying-glass h-5 w-5 text-gray-400" />
      </div>
      <input
        type="text"
        name="search_workflows"
        aria-label="Search workflows"
        value={term}
        placeholder="Search"
        onChange={event => {
          setTerm(event.target.value);
        }}
        className="block w-full rounded-md py-1.5 pl-10 pr-20 text-gray-900 placeholder:text-gray-400 focus:ring-inset focus:ring-indigo-600 sm:text-sm sm:leading-6"
      />

      <div className="absolute inset-y-0 right-0 flex items-center pr-3">
        <button
          type="button"
          className={cn(term === '' ? 'hidden' : '')}
          aria-label="Clear search"
          onClick={() => {
            setTerm('');
          }}
        >
          <span className="hero-x-mark h-5 w-5 text-gray-400" />
        </button>
      </div>
    </div>
  );
}

// --- status_card/1 ----------------------------------------------------------
function StatusCard({ state, time }: { state: WorkOrderState; time: string }) {
  return (
    <div>
      <div className="flex items-center gap-x-2">
        <span className="relative inline-flex h-2 w-2">
          {ACTIVE_STATES.includes(state) ? (
            <span
              className={cn(
                'animate-ping absolute inline-flex h-full w-full rounded-full opacity-75',
                DOT_COLOR[state]
              )}
            />
          ) : null}
          <span
            className={cn(
              'relative inline-flex rounded-full h-2 w-2',
              DOT_COLOR[state]
            )}
          />
        </span>
        <span className={cn(FONT_COLOR[state], 'font-medium')}>
          {STATE_TEXT[state]}
        </span>
      </div>
      <span className="block text-left text-gray-500 text-xs ml-4 mt-1">
        <DateTime value={time} />
      </span>
    </div>
  );
}

// --- state_card/1 (wraps status_card, or an empty placeholder) --------------
function StateCard({
  state,
  timestamp,
  period,
}: {
  state: WorkOrderState | null;
  timestamp: string;
  period: string;
}) {
  return (
    <div className="flex flex-col text-center">
      {state === null ? (
        <div className="flex items-center gap-x-2">
          <span className="inline-block h-2 w-2 bg-gray-200 rounded-full" />
          <span className="text-grey-200 italic">Nothing {period}</span>
        </div>
      ) : (
        <StatusCard state={state} time={timestamp} />
      )}
    </div>
  );
}

// --- metric_card/1 ----------------------------------------------------------
function MetricCard({
  title,
  value,
  suffix,
  link,
}: {
  title: string;
  value: ReactNode;
  suffix?: ReactNode;
  link?: ReactNode;
}) {
  return (
    <div className="bg-white shadow rounded-lg py-2 px-6">
      <h2
        className="text-sm text-gray-500"
        style={{
          fontWeight: 500,
          fontSize: '13px',
          marginBottom: '8px',
          maxWidth: '200px',
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          whiteSpace: 'nowrap',
        }}
      >
        {title}
      </h2>
      <div className="flex space-x-1 items-baseline text-3xl font-bold text-gray-800">
        <div>{value}</div>
        <div className="text-xs font-normal grow">{suffix}</div>
        <div className="text-xs font-normal">{link}</div>
      </div>
    </div>
  );
}

// --- toggle switch, as rendered by NewInputs input type="toggle" ------------
function WorkflowToggle({ defaultOn }: { defaultOn: boolean }) {
  const [on, setOn] = useState(defaultOn);
  return (
    <span className="relative inline-flex cursor-pointer items-center">
      <button
        type="button"
        role="switch"
        aria-checked={on}
        aria-label="Toggle workflow state"
        onClick={() => {
          setOn(value => !value);
        }}
        className={cn(
          'relative inline-flex h-6 w-11 rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out',
          'focus:ring-2 focus:ring-primary-500 focus:ring-offset-2 focus:outline-none',
          on ? 'bg-primary-600' : 'bg-gray-200'
        )}
      >
        <span
          className={cn(
            'pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out',
            on ? 'translate-x-5' : 'translate-x-0'
          )}
        />
      </button>
    </span>
  );
}

// --- Mock fixtures ----------------------------------------------------------
const PERIOD = 'last 30 days';

interface WorkflowRow {
  id: string;
  name: string;
  updatedAt: string;
  triggerEnabled: boolean;
  lastState: WorkOrderState | null;
  lastStateAt: string;
  workOrdersCount: number;
  stepCount: number;
  stepSuccessRate: number;
  failedCount: number;
  lastFailureAt: string | null;
}

const WORKFLOWS: WorkflowRow[] = [
  {
    id: 'wf-patient-sync',
    name: 'Patient sync',
    updatedAt: '2 hours ago',
    triggerEnabled: true,
    lastState: 'success',
    lastStateAt: '12 minutes ago',
    workOrdersCount: 1284,
    stepCount: 3,
    stepSuccessRate: 99,
    failedCount: 0,
    lastFailureAt: null,
  },
  {
    id: 'wf-dhis2-export',
    name: 'DHIS2 monthly export',
    updatedAt: 'yesterday',
    triggerEnabled: true,
    lastState: 'failed',
    lastStateAt: '1 hour ago',
    workOrdersCount: 342,
    stepCount: 5,
    stepSuccessRate: 87,
    failedCount: 14,
    lastFailureAt: '1 hour ago',
  },
  {
    id: 'wf-commcare-postgres',
    name: 'CommCare → Postgres',
    updatedAt: '3 days ago',
    triggerEnabled: true,
    lastState: 'running',
    lastStateAt: 'just now',
    workOrdersCount: 56,
    stepCount: 2,
    stepSuccessRate: 100,
    failedCount: 0,
    lastFailureAt: null,
  },
  {
    id: 'wf-kobo-intake',
    name: 'Kobo intake (disabled)',
    updatedAt: 'last week',
    triggerEnabled: false,
    lastState: null,
    lastStateAt: '',
    workOrdersCount: 0,
    stepCount: 0,
    stepSuccessRate: 0,
    failedCount: 0,
    lastFailureAt: null,
  },
];

const TD_CLASS =
  'px-3 py-4 text-sm text-gray-500 align-top first:rounded-bl-lg last:rounded-br-lg';
const TH_CLASS =
  'px-3 py-3.5 text-left text-sm font-semibold text-gray-900 whitespace-nowrap';

function WorkflowsTable() {
  return (
    <div className="w-full">
      <div className="flex justify-between mb-3">
        <h3 className="text-3xl font-bold">
          Workflows
          <span className="text-base font-normal"> ({WORKFLOWS.length})</span>
        </h3>
        <div className="flex gap-2 items-start">
          <SearchWorkflowsInput />
          <CreateWorkflowCard />
        </div>
      </div>
      <div className="bg-gray-50 shadow ring-1 ring-black/5 sm:rounded-lg">
        <table className="min-w-full divide-y divide-gray-200">
          <thead>
            <tr>
              <th scope="col" className={cn(TH_CLASS, 'pl-4 sm:pl-6')}>
                Name
              </th>
              <th scope="col" className={TH_CLASS}>
                Latest Work Order
              </th>
              <th scope="col" className={TH_CLASS}>
                Work Orders
              </th>
              <th scope="col" className={TH_CLASS}>
                Work Orders in a failed state
              </th>
              <th scope="col" className={TH_CLASS}>
                Enabled
              </th>
              <th scope="col" className={cn(TH_CLASS, 'pr-4 sm:pr-6')}>
                <span className="sr-only">Actions</span>
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200 bg-white">
            {WORKFLOWS.map(workflow => (
              <tr
                key={workflow.id}
                className="hover:bg-gray-100 transition-colors duration-200"
              >
                <td
                  className={cn(
                    TD_CLASS,
                    'pl-4 sm:pl-6 wrap-break-word max-w-[15rem]'
                  )}
                >
                  <div className="cursor-pointer">
                    <WorkflowCard
                      workflow={{
                        id: workflow.id,
                        name: workflow.name,
                        updatedAt: workflow.updatedAt,
                        triggerEnabled: workflow.triggerEnabled,
                      }}
                    />
                  </div>
                </td>
                <td className={cn(TD_CLASS, 'wrap-break-word max-w-[15rem]')}>
                  <StateCard
                    state={workflow.lastState}
                    timestamp={workflow.lastStateAt}
                    period={PERIOD}
                  />
                </td>
                <td className={cn(TD_CLASS, 'wrap-break-word max-w-[10rem]')}>
                  {workflow.workOrdersCount > 0 ? (
                    <div>
                      <div className="text-indigo-700 text-lg">
                        <a href="#history" className="hover:underline">
                          {workflow.workOrdersCount}
                        </a>
                      </div>
                      <div className="text-gray-500 text-xs">
                        ({workflow.stepCount} steps,{' '}
                        <span>{workflow.stepSuccessRate}% success</span>)
                      </div>
                    </div>
                  ) : (
                    <div>
                      <div className="text-gray-400 text-lg">
                        <span>0</span>
                      </div>
                      <div className="text-xs">
                        <span>N/A</span>
                      </div>
                    </div>
                  )}
                </td>
                <td className={cn(TD_CLASS, 'wrap-break-word max-w-[15rem]')}>
                  {workflow.failedCount > 0 ? (
                    <div>
                      <div className="text-indigo-700 text-lg">
                        <a href="#history" className="hover:underline">
                          {workflow.failedCount}
                        </a>
                      </div>
                      <div className="text-gray-500 text-xs">
                        Latest failure{' '}
                        <DateTime value={workflow.lastFailureAt ?? ''} />
                      </div>
                    </div>
                  ) : (
                    <div>
                      <div className="text-gray-400 text-lg">
                        <span>0</span>
                      </div>
                      <div className="text-xs mt-1">
                        <span>N/A</span>
                      </div>
                    </div>
                  )}
                </td>
                <td className={TD_CLASS}>
                  <WorkflowToggle defaultOn={workflow.triggerEnabled} />
                </td>
                <td className={cn(TD_CLASS, 'pr-4 sm:pr-6 text-right')}>
                  <a href="#delete" className="table-action">
                    Delete
                  </a>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// --- welcome_banner/1 (TypewriterHook replaced with static text) ------------
function WelcomeBanner({ userName }: { userName: string }) {
  return (
    <div className="mb-2 min-h-[100px]">
      <div className="flex justify-between items-center pt-6">
        <h1 className="text-2xl font-medium">
          <span>Good morning, {userName}!</span>
        </h1>
      </div>
      <div>
        <p className="mb-6 mt-4">
          Click on a project to get started. If you need some help, head to{' '}
          <a
            href="https://docs.openfn.org"
            target="_blank"
            rel="noreferrer"
            className="link"
          >
            docs.openfn.org
          </a>{' '}
          or{' '}
          <a
            href="https://community.openfn.org"
            target="_blank"
            rel="noreferrer"
            className="link"
          >
            community.openfn.org
          </a>{' '}
          to learn more.
        </p>
      </div>
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Dashboard (LiveView Clone)',
  tags: ['useful', 'bespoke'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const WorkflowList: Story = {
  name: 'Workflow list',
  render: () => (
    <Showcase className="min-w-[960px]">
      <Section
        title="workflow_list / workflows_table"
        description="The project dashboard's workflow table: a sortable header, per-row workflow card, latest work-order state, counts and an enabled toggle. Search and create-workflow controls sit in the header."
      >
        <WorkflowsTable />
      </Section>
    </Showcase>
  ),
};

export const ProjectMetrics: Story = {
  name: 'Project metrics',
  render: () => (
    <Showcase className="min-w-[960px]">
      <Section
        title="project_metrics / metric_card"
        description="The four summary cards shown above the workflow table, covering work orders, runs, successful runs and failures over the reporting period."
      >
        <div className="grid gap-12 md:grid-cols-2 lg:grid-cols-4">
          <MetricCard
            title="Work Orders"
            value={1682}
            suffix={
              <a href="#pending" className="link">
                (8 pending)
              </a>
            }
          />
          <MetricCard title="Runs" value={4127} suffix={<>(12 pending)</>} />
          <MetricCard
            title="Successful Runs"
            value={3981}
            suffix={<>(96%)</>}
          />
          <MetricCard
            title="Work Orders in failed state"
            value={146}
            suffix={<>(4%)</>}
            link={
              <a href="#failed" className="link">
                View all
              </a>
            }
          />
        </div>
      </Section>
    </Showcase>
  ),
};

export const Cards: Story = {
  render: () => (
    <Showcase className="min-w-[640px]">
      <Section
        title="workflow_card/1"
        description="A workflow's name and last-updated line. Disabled triggers render the name in gray."
      >
        <div className="flex flex-col gap-4">
          <WorkflowCard
            workflow={{
              id: 'wf-1',
              name: 'Patient sync',
              updatedAt: '2 hours ago',
              triggerEnabled: true,
            }}
          />
          <WorkflowCard
            workflow={{
              id: 'wf-2',
              name: 'Kobo intake (disabled)',
              updatedAt: 'last week',
              triggerEnabled: false,
            }}
          />
        </div>
      </Section>

      <Section
        title="create_workflow_card/1"
        description="The primary call-to-action, and its disabled state when the user lacks permission."
      >
        <div className="flex gap-4">
          <div className="w-56">
            <CreateWorkflowCard />
          </div>
          <div className="w-56">
            <CreateWorkflowCard disabled />
          </div>
        </div>
      </Section>

      <Section
        title="search_workflows_input/1"
        description="Search box with a leading magnifying glass; the clear button appears once you type."
      >
        <div className="max-w-sm">
          <SearchWorkflowsInput />
        </div>
      </Section>
    </Showcase>
  ),
};

export const StateAndStatus: Story = {
  name: 'State & status cards',
  render: () => (
    <Showcase className="min-w-[640px]">
      <Section
        title="status_card/1"
        description="A run-state dot and label. Active states (pending, running) animate with a ping."
      >
        <div className="grid grid-cols-2 gap-x-12 gap-y-4 sm:grid-cols-3">
          {(Object.keys(STATE_TEXT) as WorkOrderState[]).map(state => (
            <StatusCard key={state} state={state} time="12 minutes ago" />
          ))}
        </div>
      </Section>

      <Section
        title="state_card/1"
        description="Wraps status_card, falling back to a muted placeholder when there is no activity in the period."
      >
        <div className="flex flex-col gap-4">
          <StateCard
            state="success"
            timestamp="12 minutes ago"
            period={PERIOD}
          />
          <StateCard state={null} timestamp="" period={PERIOD} />
        </div>
      </Section>
    </Showcase>
  ),
};

export const WelcomeBannerStory: Story = {
  name: 'Welcome banner',
  render: () => (
    <Showcase className="min-w-[640px]">
      <Section
        title="welcome_banner/1"
        description="The greeting at the top of the dashboard. The live version animates the text via a TypewriterHook; here it is shown fully typed."
      >
        <WelcomeBanner userName="Amara" />
      </Section>
    </Showcase>
  ),
};
