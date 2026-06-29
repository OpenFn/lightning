import type { Meta, StoryObj } from '@storybook/react-vite';
import { useState } from 'react';

import { cn } from '#/utils/cn';

import {
  AppSidebar,
  TopBar,
  Breadcrumbs,
  Crumb,
  ProjectCrumb,
  PageFrame,
  ContentArea,
  Centered,
} from '../liveview/_shell';
import { Table, Tr, Th, Td, TableBody } from '../liveview/_table';

/**
 * Composite view: the History page (run_live/index.html.heex). Assembles the
 * project sidebar, header + breadcrumbs, the pill tab bar (Work Orders /
 * Channel Logs), a filter row and the Work Orders table into one screen.
 * Presentational only.
 */
type RunState = 'success' | 'failed' | 'running' | 'pending' | 'cancelled';

const STATE_PILL: Record<RunState, string> = {
  success: 'bg-green-100 text-green-700',
  failed: 'bg-red-100 text-red-700',
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

const ROWS: { id: string; workflow: string; state: RunState; when: string }[] = [
  { id: 'a1b2c3d4', workflow: 'Patient sync', state: 'success', when: '2 min ago' },
  { id: 'e5f6a7b8', workflow: 'DHIS2 export', state: 'failed', when: '14 min ago' },
  { id: 'c9d0e1f2', workflow: 'CommCare → Postgres', state: 'running', when: '1 hr ago' },
  { id: '3a4b5c6d', workflow: 'Nightly aggregation', state: 'pending', when: '3 hr ago' },
];

function PillTabs() {
  const [active, setActive] = useState('work-orders');
  const tabs = [
    { id: 'work-orders', label: 'Work Orders' },
    { id: 'channel-logs', label: 'Channel Logs' },
  ];
  return (
    <div className="w-fit rounded-lg bg-slate-100 p-1">
      <nav className="flex gap-1" aria-label="History tabs">
        {tabs.map(tab => (
          <button
            key={tab.id}
            type="button"
            onClick={() => {
              setActive(tab.id);
            }}
            className={cn(
              'rounded-md px-3 py-2 text-sm font-medium transition-all',
              tab.id === active
                ? 'bg-white text-indigo-600'
                : 'text-gray-500 hover:bg-slate-50 hover:text-gray-700'
            )}
          >
            {tab.label}
          </button>
        ))}
      </nav>
    </div>
  );
}

const meta = {
  title: 'Pages/History',
  tags: ['composite'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Default: Story = {
  render: () => (
    <PageFrame sidebar={<AppSidebar variant="project" activeItem="runs" />}>
      <TopBar>
        <Breadcrumbs>
          <ProjectCrumb label="openhie-demo" />
          <Crumb>History</Crumb>
        </Breadcrumbs>
      </TopBar>
      <ContentArea>
        <Centered>
          <div className="flex flex-col gap-4">
            <div className="flex items-center justify-between">
              <PillTabs />
              <button
                type="button"
                className="cursor-pointer rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-gray-300 ring-inset hover:bg-gray-50"
              >
                Export
              </button>
            </div>

            <div className="flex flex-wrap items-center gap-2">
              <span className="inline-flex items-center gap-x-1 rounded-full border border-indigo-200 bg-indigo-50 py-1.5 pr-3 pl-3 text-sm font-medium text-indigo-700">
                Status: success
              </span>
              <span className="inline-flex items-center gap-x-1 rounded-full border border-gray-200 bg-gray-100 py-1.5 pr-3 pl-3 text-sm font-medium text-gray-700">
                Workflow
              </span>
              <div className="grow" />
              <input
                type="text"
                aria-label="Search work orders"
                placeholder="Search…"
                className="block w-56 rounded-lg border-slate-300 text-slate-900 focus:border-slate-400 focus:ring-0 focus:outline-primary-600 sm:text-sm"
              />
            </div>

            <Table>
              <thead>
                <Tr>
                  <Th>ID</Th>
                  <Th>Workflow</Th>
                  <Th sortable active direction="desc">
                    Created
                  </Th>
                  <Th className="text-right">Status</Th>
                </Tr>
              </thead>
              <TableBody>
                {ROWS.map(row => (
                  <Tr key={row.id}>
                    <Td>
                      <span className="font-mono text-xs text-primary-400">
                        {row.id}
                      </span>
                    </Td>
                    <Td>
                      <span className="font-medium text-gray-900">
                        {row.workflow}
                      </span>
                    </Td>
                    <Td>{row.when}</Td>
                    <Td className="text-right">
                      <StatusPill state={row.state} />
                    </Td>
                  </Tr>
                ))}
              </TableBody>
            </Table>
          </div>
        </Centered>
      </ContentArea>
    </PageFrame>
  ),
};
