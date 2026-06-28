import type { Meta, StoryObj } from '@storybook/react-vite';

import { Showcase, Section } from '../_shared/showcase';

import { Table, Tr, Th, Td, TableBody, ActionsButton } from './_table';

/**
 * React clones of two more domain tables:
 * - `LightningWeb.UserLive.Components.users_table/1`
 *   (lib/lightning_web/live/user_live/components.ex) — the superuser admin
 *   users list, with a filter input above and the superuser footnote below.
 * - `LightningWeb.DashboardLive.Components.user_projects_table/1`
 *   (lib/lightning_web/live/dashboard_live/components.ex) — the projects list
 *   on the dashboard, with clickable rows.
 *
 * Presentational only — filtering, sorting and navigation are not wired up.
 */
function CheckMark() {
  return <span className="hero-check-circle-solid h-6 w-6 text-gray-500" />;
}

const meta = {
  title: 'LiveView Clones/Admin Tables (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Users: Story = {
  render: () => (
    <Showcase className="min-w-[1040px]">
      <Section
        title="users_table"
        description="The superuser admin users list. Filter input above, footnote below."
      >
        <div className="flex flex-col gap-3">
          <div className="max-w-xs">
            <input
              type="text"
              aria-label="Filter users"
              placeholder="Filter users..."
              className="block w-full rounded-lg border-slate-300 text-slate-900 focus:border-slate-400 focus:ring-0 focus:outline-primary-600 sm:text-sm"
            />
          </div>
          <Table>
            <thead>
              <Tr>
                <Th sortable active>
                  First name
                </Th>
                <Th sortable>Last name</Th>
                <Th sortable>Email</Th>
                <Th sortable>Role*</Th>
                <Th sortable>Enabled?</Th>
                <Th sortable>Support?</Th>
                <Th sortable>Scheduled Deletion</Th>
                <Th>Actions</Th>
              </Tr>
            </thead>
            <TableBody>
              <Tr>
                <Td className="max-w-40 text-gray-900">Amara</Td>
                <Td className="max-w-40">Okafor</Td>
                <Td className="max-w-48">amara@example.org</Td>
                <Td>superuser</Td>
                <Td>
                  <CheckMark />
                </Td>
                <Td>
                  <CheckMark />
                </Td>
                <Td />
                <Td className="py-0.5">
                  <ActionsButton />
                </Td>
              </Tr>
              <Tr>
                <Td className="max-w-40 text-gray-900">Wei</Td>
                <Td className="max-w-40">Chen</Td>
                <Td className="max-w-48">wei@example.org</Td>
                <Td>user</Td>
                <Td>
                  <CheckMark />
                </Td>
                <Td />
                <Td>28 Jun 14:30</Td>
                <Td className="py-0.5">
                  <ActionsButton />
                </Td>
              </Tr>
            </TableBody>
          </Table>
          <p className="text-sm text-gray-500">
            *Note that a <code>superuser</code> can access{' '}
            <em>everything</em> in a Lightning installation across all projects.
          </p>
        </div>
      </Section>
    </Showcase>
  ),
};

export const Projects: Story = {
  render: () => (
    <Showcase className="min-w-[880px]">
      <Section
        title="user_projects_table"
        description="The dashboard projects list. Rows are clickable (navigate to the project)."
      >
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
              <Td className="max-w-[25rem]">Admin</Td>
              <Td className="max-w-[10rem]">7</Td>
              <Td className="max-w-[5rem]">
                <a className="link" href="https://docs.openfn.org">
                  4
                </a>
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
              <Td className="max-w-[25rem]">Editor</Td>
              <Td className="max-w-[10rem]">2</Td>
              <Td className="max-w-[5rem]">
                <a className="link" href="https://docs.openfn.org">
                  9
                </a>
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
      </Section>
    </Showcase>
  ),
};
