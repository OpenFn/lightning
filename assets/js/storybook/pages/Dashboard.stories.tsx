import type { Meta, StoryObj } from '@storybook/react-vite';

import {
  AppSidebar,
  TopBar,
  PageFrame,
  ContentArea,
  Centered,
} from '../liveview/_shell';
import { Table, Tr, Th, Td, TableBody } from '../liveview/_table';

/**
 * Composite view: the projects dashboard (the `/projects` landing page —
 * dashboard_live + dashboard_components.ex). Assembles the profile sidebar, the
 * header, a welcome banner, the project-metrics cards and the projects table
 * into one screen. Presentational only.
 */
const METRICS = [
  { label: 'Work Orders', value: '1,284' },
  { label: 'Runs (30d)', value: '3,902' },
  { label: 'Successful Runs', value: '96.4%' },
  { label: 'Failed (30d)', value: '142' },
];

function MetricCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg bg-white p-4 shadow-xs ring-1 ring-gray-200">
      <div className="text-xs font-medium tracking-wide text-gray-500 uppercase">
        {label}
      </div>
      <div className="mt-1 text-2xl font-semibold text-gray-900">{value}</div>
    </div>
  );
}

const meta = {
  title: 'Pages/Dashboard',
  tags: ['composite'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Default: Story = {
  render: () => (
    <PageFrame sidebar={<AppSidebar variant="profile" activeItem="projects" />}>
      <TopBar>
        <h1 className="flex items-center text-xl font-semibold text-secondary-900">
          Projects
        </h1>
      </TopBar>
      <ContentArea>
        <Centered>
          <div className="flex flex-col gap-6">
            <div className="rounded-lg bg-gradient-to-br from-primary-700 to-primary-400 p-6 text-white">
              <h2 className="text-lg font-semibold">Welcome back, Amara 👋</h2>
              <p className="mt-1 text-sm text-white/80">
                Here's what's been happening across your projects.
              </p>
            </div>

            <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
              {METRICS.map(metric => (
                <MetricCard
                  key={metric.label}
                  label={metric.label}
                  value={metric.value}
                />
              ))}
            </div>

            <div>
              <div className="mb-3 flex items-center justify-between">
                <h6 className="font-normal text-black">Projects (2)</h6>
                <button
                  type="button"
                  className="cursor-pointer rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-primary-500"
                >
                  Create project
                </button>
              </div>
              <Table>
                <thead>
                  <Tr>
                    <Th sortable active>
                      Name
                    </Th>
                    <Th>Role</Th>
                    <Th>Workflows</Th>
                    <Th>Collaborators</Th>
                    <Th sortable>Last Updated</Th>
                    <Th />
                  </Tr>
                </thead>
                <TableBody>
                  <Tr className="cursor-pointer hover:bg-gray-100">
                    <Td className="text-gray-900">openhie-demo</Td>
                    <Td>Admin</Td>
                    <Td>7</Td>
                    <Td>
                      <span className="link">4</span>
                    </Td>
                    <Td>3 hours ago</Td>
                    <Td>
                      <div className="flex justify-end">
                        <span className="hero-chevron-right h-5 w-5 text-gray-400" />
                      </div>
                    </Td>
                  </Tr>
                  <Tr className="cursor-pointer hover:bg-gray-100">
                    <Td className="text-gray-900">moh-reporting</Td>
                    <Td>Editor</Td>
                    <Td>2</Td>
                    <Td>
                      <span className="link">9</span>
                    </Td>
                    <Td>Yesterday</Td>
                    <Td>
                      <div className="flex justify-end">
                        <span className="hero-chevron-right h-5 w-5 text-gray-400" />
                      </div>
                    </Td>
                  </Tr>
                </TableBody>
              </Table>
            </div>
          </div>
        </Centered>
      </ContentArea>
    </PageFrame>
  ),
};
