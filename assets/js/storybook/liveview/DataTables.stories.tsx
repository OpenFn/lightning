import type { Meta, StoryObj } from '@storybook/react-vite';

import { Showcase, Section } from '../_shared/showcase';

import {
  Table,
  Tr,
  Th,
  Td,
  TableBody,
  AccessChip,
  CodeChip,
  ActionsButton,
} from './_table';

/**
 * React clones of the tables in `LightningWeb.Components.DataTables`
 * (lib/lightning_web/live/components/data_tables.ex): credentials_table,
 * keychain_credentials_table, oauth_clients_table, history_exports_table,
 * collections_table and collaborators_table.
 *
 * Presentational only — sorting, the Actions dropdowns and the failure-alert /
 * digest selects are not wired up. Built on the shared Table primitive clones.
 */
function EnvCount({ count, envs }: { count: number; envs: string }) {
  return (
    <span
      className="cursor-default text-base text-gray-700"
      title={envs}
      aria-label={envs}
    >
      {count}
    </span>
  );
}

const meta = {
  title: 'LiveView Clones/Data Tables (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Credentials: Story = {
  render: () => (
    <Showcase className="min-w-[980px]">
      <Section
        title="credentials_table"
        description="Project credentials with type, access, external ID and environment count."
      >
        <Table>
          <thead>
            <Tr>
              <Th>Name</Th>
              <Th>Type</Th>
              <Th>Owner</Th>
              <Th>Projects with access</Th>
              <Th>External ID</Th>
              <Th>Environments</Th>
              <Th>
                <span className="sr-only">Actions</span>
              </Th>
            </Tr>
          </thead>
          <TableBody>
            <Tr>
              <Td className="max-w-[15rem]">
                <span className="font-medium text-gray-900">DHIS2 prod</span>
              </Td>
              <Td>dhis2</Td>
              <Td>amara@example.org</Td>
              <Td className="max-w-[25rem]">
                <AccessChip>Patient sync</AccessChip>{' '}
                <AccessChip>Reporting</AccessChip>
              </Td>
              <Td>
                <CodeChip>ext-9f2a</CodeChip>
              </Td>
              <Td className="text-left">
                <EnvCount count={2} envs="main, staging" />
              </Td>
              <Td>
                <div className="flex items-center justify-end">
                  <ActionsButton />
                </div>
              </Td>
            </Tr>
            <Tr>
              <Td className="max-w-[15rem]">
                <div className="flex items-center text-gray-900">
                  Salesforce
                  <span
                    className="ml-2"
                    title="OAuth client not found"
                    aria-label="OAuth client not found"
                  >
                    <span className="hero-exclamation-triangle h-5 w-5 text-yellow-500" />
                  </span>
                </div>
              </Td>
              <Td>salesforce</Td>
              <Td>wei@example.org</Td>
              <Td className="max-w-[25rem]">
                <AccessChip>CommCare → Postgres</AccessChip>
              </Td>
              <Td>
                <span className="text-sm text-gray-400">-</span>
              </Td>
              <Td className="text-left">
                <EnvCount count={1} envs="main" />
              </Td>
              <Td>
                <div className="flex items-center justify-end">
                  <ActionsButton />
                </div>
              </Td>
            </Tr>
          </TableBody>
        </Table>
      </Section>
    </Showcase>
  ),
};

export const KeychainCredentials: Story = {
  render: () => (
    <Showcase className="min-w-[820px]">
      <Section
        title="keychain_credentials_table"
        description="Keychain credentials select a credential per run via a JSONPath."
      >
        <Table>
          <thead>
            <Tr>
              <Th>Name</Th>
              <Th>Path</Th>
              <Th>Default Credential</Th>
              <Th>Owner</Th>
              <Th>
                <span className="sr-only">Actions</span>
              </Th>
            </Tr>
          </thead>
          <TableBody>
            <Tr>
              <Td className="max-w-[15rem] text-gray-900">Region keychain</Td>
              <Td className="max-w-[25rem]">
                <CodeChip>$.data.region</CodeChip>
              </Td>
              <Td>DHIS2 prod</Td>
              <Td>amara@example.org</Td>
              <Td>
                <div className="flex items-center justify-end">
                  <ActionsButton />
                </div>
              </Td>
            </Tr>
            <Tr>
              <Td className="max-w-[15rem] text-gray-900">Facility keychain</Td>
              <Td className="max-w-[25rem]">
                <CodeChip>$.facility.id</CodeChip>
              </Td>
              <Td>
                <span className="text-sm text-gray-400">None</span>
              </Td>
              <Td>wei@example.org</Td>
              <Td>
                <div className="flex items-center justify-end">
                  <ActionsButton />
                </div>
              </Td>
            </Tr>
          </TableBody>
        </Table>
      </Section>
    </Showcase>
  ),
};

export const OauthClients: Story = {
  render: () => (
    <Showcase className="min-w-[900px]">
      <Section
        title="oauth_clients_table"
        description="Registered OAuth clients, their access and authorization endpoints."
      >
        <Table>
          <thead>
            <Tr>
              <Th>Name</Th>
              <Th>Owner</Th>
              <Th>Projects With Access</Th>
              <Th>Authorization URL</Th>
              <Th>
                <span className="sr-only">Actions</span>
              </Th>
            </Tr>
          </thead>
          <TableBody>
            <Tr>
              <Td className="max-w-[15rem] text-gray-900">Google</Td>
              <Td>GLOBAL</Td>
              <Td className="max-w-[20rem]">
                <AccessChip>Patient sync</AccessChip>{' '}
                <AccessChip>Reporting</AccessChip>
              </Td>
              <Td className="max-w-[18rem]">
                https://accounts.google.com/o/oauth2/v2/auth
              </Td>
              <Td>
                <div className="flex items-center justify-end">
                  <ActionsButton />
                </div>
              </Td>
            </Tr>
            <Tr>
              <Td className="max-w-[15rem] text-gray-900">Salesforce</Td>
              <Td>amara@example.org</Td>
              <Td className="max-w-[20rem]">
                <AccessChip>CommCare → Postgres</AccessChip>
              </Td>
              <Td className="max-w-[18rem]">
                https://login.salesforce.com/services/oauth2/authorize
              </Td>
              <Td>
                <div className="flex items-center justify-end">
                  <ActionsButton />
                </div>
              </Td>
            </Tr>
          </TableBody>
        </Table>
      </Section>
    </Showcase>
  ),
};

export const HistoryExports: Story = {
  render: () => (
    <Showcase className="min-w-[820px]">
      <Section
        title="history_exports_table"
        description="Requested history exports and their processing status."
      >
        <Table>
          <thead>
            <Tr>
              <Th>Export Date</Th>
              <Th>Filename</Th>
              <Th>Export Requested By</Th>
              <Th>Status</Th>
              <Th />
            </Tr>
          </thead>
          <TableBody>
            <Tr>
              <Td>2 hours ago</Td>
              <Td className="text-gray-900">history-2026-06-28.zip</Td>
              <Td>Amara Okafor</Td>
              <Td>Completed</Td>
              <Td>
                <div className="flex justify-end py-0.5">
                  <a className="link" href="https://docs.openfn.org">
                    Download
                  </a>
                </div>
              </Td>
            </Tr>
            <Tr>
              <Td>just now</Td>
              <Td>
                <em>Pending</em>
              </Td>
              <Td>Wei Chen</Td>
              <Td>Enqueued</Td>
              <Td>
                <div className="flex justify-end py-0.5" />
              </Td>
            </Tr>
          </TableBody>
        </Table>
      </Section>
    </Showcase>
  ),
};

export const Collections: Story = {
  render: () => (
    <Showcase className="min-w-[640px]">
      <Section
        title="collections_table"
        description="Key-value collections with sortable name and used storage."
      >
        <Table>
          <thead>
            <Tr>
              <Th sortable active>
                Name
              </Th>
              <Th sortable>Used storage</Th>
              <Th>
                <span className="sr-only">Actions</span>
              </Th>
            </Tr>
          </thead>
          <TableBody>
            <Tr>
              <Td className="text-gray-900">patient-records</Td>
              <Td>2.4 MB</Td>
              <Td>
                <div className="flex justify-end py-0.5">
                  <ActionsButton />
                </div>
              </Td>
            </Tr>
            <Tr>
              <Td className="text-gray-900">facility-cache</Td>
              <Td>184 KB</Td>
              <Td>
                <div className="flex justify-end py-0.5">
                  <ActionsButton />
                </div>
              </Td>
            </Tr>
          </TableBody>
        </Table>
      </Section>
    </Showcase>
  ),
};

function AlertSelect({
  label,
  options,
  value,
}: {
  label: string;
  options: string[];
  value: string;
}) {
  return (
    <select
      aria-label={label}
      defaultValue={value}
      className="rounded-lg border-slate-300 text-sm focus:border-slate-400 focus:ring-0 focus:outline-primary-600 sm:text-sm"
    >
      {options.map(option => (
        <option key={option}>{option}</option>
      ))}
    </select>
  );
}

export const Collaborators: Story = {
  render: () => (
    <Showcase className="min-w-[900px]">
      <Section
        title="collaborators_table"
        description="Project members with role, failure-alert and digest preferences."
      >
        <Table>
          <thead>
            <Tr>
              <Th>Collaborator</Th>
              <Th>Role</Th>
              <Th>Failure Alert</Th>
              <Th>Digest</Th>
              <Th>
                <span className="sr-only">Actions</span>
              </Th>
            </Tr>
          </thead>
          <TableBody>
            <Tr>
              <Td>
                <div className="text-gray-900">Amara Okafor</div>
                <span className="text-xs">amara@example.org</span>
                <div>
                  <small className="text-gray-400">
                    <em>Well hello, you!</em>
                  </small>
                </div>
              </Td>
              <Td>Admin</Td>
              <Td>
                <AlertSelect
                  label="Failure alert for Amara"
                  options={['Enabled', 'Disabled']}
                  value="Enabled"
                />
              </Td>
              <Td>
                <AlertSelect
                  label="Digest for Amara"
                  options={['Never', 'Daily', 'Weekly', 'Monthly']}
                  value="Weekly"
                />
              </Td>
              <Td>
                <div className="flex justify-end py-0.5">
                  <ActionsButton />
                </div>
              </Td>
            </Tr>
            <Tr>
              <Td>
                <div className="text-gray-900">Wei Chen</div>
                <span className="text-xs">wei@example.org</span>
              </Td>
              <Td>Editor</Td>
              <Td>
                <AlertSelect
                  label="Failure alert for Wei"
                  options={['Enabled', 'Disabled']}
                  value="Disabled"
                />
              </Td>
              <Td>
                <AlertSelect
                  label="Digest for Wei"
                  options={['Never', 'Daily', 'Weekly', 'Monthly']}
                  value="Daily"
                />
              </Td>
              <Td>
                <div className="flex justify-end py-0.5">
                  <ActionsButton />
                </div>
              </Td>
            </Tr>
          </TableBody>
        </Table>
      </Section>
    </Showcase>
  ),
};
