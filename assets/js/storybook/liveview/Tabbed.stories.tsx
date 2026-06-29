import type { Meta, StoryObj } from '@storybook/react-vite';
import { useState } from 'react';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clone of `LightningWeb.Components.Tabbed`
 * (lib/lightning_web/live/components/tabbed.ex): `tabs/1`, `tab/1`, `panel/1`
 * and `panels/1`, rendered as a tabbed selector.
 *
 * Presentational only — the server component wires tab/panel visibility via
 * the `TabbedSelector`/`TabbedContainer` JS hooks and URL hashes; here the
 * active hash lives in local state and `<a href="##{hash}">` tabs become
 * `<button>`s. The tab styling mirrors the `.tabbed-selector[role='tablist']`
 * rules in assets/css/app.css (secondary/primary resolve to gray/indigo).
 */
interface TabItem {
  hash: string;
  label: ReactNode;
  disabled?: boolean;
  disabledMsg?: string;
}

const TAB_BASE =
  'text-sm font-semibold text-gray-700 py-2 px-1 border-b-2 border-transparent leading-tight';
const TAB_SELECTED = 'border-b-indigo-500 text-indigo-600';
const TAB_UNSELECTED =
  'text-gray-500 hover:text-gray-600 hover:border-b-gray-300';

function TabbedSelector({
  id,
  tabs,
  panels,
  orientation = 'horizontal',
}: {
  id: string;
  tabs: TabItem[];
  panels: Record<string, ReactNode>;
  orientation?: 'horizontal' | 'vertical';
}) {
  const firstEnabled = tabs.find(tab => !tab.disabled)?.hash ?? tabs[0]?.hash;
  const [active, setActive] = useState(firstEnabled ?? '');

  const tablist = (
    <div
      role="tablist"
      className={cn(
        'tabbed-selector',
        orientation === 'horizontal'
          ? 'flex flex-row space-x-4'
          : 'flex flex-none flex-col space-y-4 pr-8'
      )}
    >
      {tabs.map(tab => {
        const selected = tab.hash === active;
        if (tab.disabled) {
          return (
            <span
              key={tab.hash}
              id={`${tab.hash}-tab`}
              role="tab"
              aria-controls={`${tab.hash}-panel`}
              aria-selected="false"
              aria-disabled="true"
              aria-label={tab.disabledMsg}
              title={tab.disabledMsg}
              className={cn(
                TAB_BASE,
                TAB_UNSELECTED,
                'hover:cursor-not-allowed',
                orientation === 'vertical' && 'px-4'
              )}
            >
              {tab.label}
            </span>
          );
        }
        return (
          <button
            key={tab.hash}
            type="button"
            id={`${tab.hash}-tab`}
            role="tab"
            aria-controls={`${tab.hash}-panel`}
            aria-selected={selected}
            onClick={() => {
              setActive(tab.hash);
            }}
            className={cn(
              TAB_BASE,
              selected ? TAB_SELECTED : TAB_UNSELECTED,
              orientation === 'vertical' && 'px-4'
            )}
          >
            {tab.label}
          </button>
        );
      })}
    </div>
  );

  const panelList = tabs.map(tab => (
    <div
      key={tab.hash}
      id={`${tab.hash}-panel`}
      role="tabpanel"
      aria-labelledby={`${tab.hash}-tab`}
      className={cn('flex', tab.hash === active ? '' : 'hidden')}
    >
      {panels[tab.hash]}
    </div>
  ));

  return (
    <div
      id={id}
      className={cn(
        orientation === 'horizontal'
          ? 'flex flex-col gap-x-4 gap-y-2'
          : 'flex flex-row gap-y-2'
      )}
    >
      {orientation === 'horizontal' ? (
        <>
          {tablist}
          {panelList}
        </>
      ) : (
        <>
          {tablist}
          <div className="grow">{panelList}</div>
        </>
      )}
    </div>
  );
}

function PanelBody({ children }: { children: ReactNode }) {
  return (
    <div className="w-full rounded-md border border-gray-200 bg-white p-4 text-sm text-gray-700">
      {children}
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Tabbed Selector (LiveView Clone)',
  tags: ['useful'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Horizontal: Story = {
  name: 'Horizontal tabs',
  render: () => (
    <Showcase className="min-w-[560px]">
      <Section
        title="tabs/1 + panels/1"
        description="The horizontal tabbed selector used across settings and credential pages. Click a tab to reveal its panel."
      >
        <TabbedSelector
          id="settings-tabs"
          tabs={[
            { hash: 'collaborators', label: 'Collaborators' },
            { hash: 'credentials', label: 'Credentials' },
            { hash: 'webhooks', label: 'Webhook Security' },
            { hash: 'data-storage', label: 'Data Storage' },
          ]}
          panels={{
            collaborators: (
              <PanelBody>
                Manage who can access this project and their roles.
              </PanelBody>
            ),
            credentials: (
              <PanelBody>
                Project credentials shared with collaborators for running jobs.
              </PanelBody>
            ),
            webhooks: (
              <PanelBody>
                Configure webhook authentication methods for incoming triggers.
              </PanelBody>
            ),
            'data-storage': (
              <PanelBody>
                Choose how long input and output dataclips are retained.
              </PanelBody>
            ),
          }}
        />
      </Section>
    </Showcase>
  ),
};

export const WithDisabledTab: Story = {
  name: 'With a disabled tab',
  render: () => (
    <Showcase className="min-w-[560px]">
      <Section
        title="tab/1 — disabled"
        description="A disabled tab renders as a non-interactive span with a not-allowed cursor and a tooltip explaining why."
      >
        <TabbedSelector
          id="run-tabs"
          tabs={[
            { hash: 'log', label: 'Log' },
            { hash: 'input', label: 'Input' },
            { hash: 'output', label: 'Output' },
            {
              hash: 'audit',
              label: 'Audit',
              disabled: true,
              disabledMsg: 'Auditing is available on Enterprise plans only',
            },
          ]}
          panels={{
            log: <PanelBody>Streaming console output for this run.</PanelBody>,
            input: <PanelBody>The dataclip passed into the first step.</PanelBody>,
            output: <PanelBody>The final state emitted by the run.</PanelBody>,
            audit: <PanelBody>Audit trail for this run.</PanelBody>,
          }}
        />
      </Section>
    </Showcase>
  ),
};

export const Vertical: Story = {
  name: 'Vertical tabs',
  render: () => (
    <Showcase className="min-w-[560px]">
      <Section
        title="container/1 — vertical orientation"
        description="The vertical layout places the tablist beside the panels, with each tab padded by px-4."
      >
        <TabbedSelector
          id="profile-tabs"
          orientation="vertical"
          tabs={[
            { hash: 'details', label: 'Details' },
            { hash: 'security', label: 'Security' },
            { hash: 'tokens', label: 'API Tokens' },
          ]}
          panels={{
            details: <PanelBody>Update your name and email address.</PanelBody>,
            security: (
              <PanelBody>Change your password and manage MFA.</PanelBody>
            ),
            tokens: (
              <PanelBody>Personal access tokens for the CLI and API.</PanelBody>
            ),
          }}
        />
      </Section>
    </Showcase>
  ),
};
