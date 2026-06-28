import type { Meta, StoryObj } from '@storybook/react-vite';
import { useState } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clone of `LightningWeb.Components.TabBar.pill_tabs/1`
 * (lib/lightning_web/components/tab_bar.ex). The original navigates via
 * `<.link patch={...}>`; here the active tab is tracked in local state.
 */
interface Tab {
  id: string;
  label: string;
}

function PillTabs({ tabs }: { tabs: Tab[] }) {
  const [active, setActive] = useState(tabs[0]?.id ?? '');
  return (
    <div className="rounded-lg bg-slate-100 p-1">
      <nav className="flex gap-1" aria-label="Tabs">
        {tabs.map(tab => (
          <button
            key={tab.id}
            type="button"
            onClick={() => {
              setActive(tab.id);
            }}
            className={cn(
              'rounded-md px-3 py-2 text-sm font-medium transition-all duration-200',
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
  title: 'LiveView Clones/Tab Bar (LiveView Clone)',
  parameters: { layout: 'centered' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const PillStyle: Story = {
  name: 'Pill tabs',
  render: () => (
    <Showcase>
      <Section
        title="pill_tabs/1"
        description="Pill-style tab bar used on the History page (Work Orders / Channel Logs)."
      >
        <PillTabs
          tabs={[
            { id: 'work-orders', label: 'Work Orders' },
            { id: 'channel-logs', label: 'Channel Logs' },
          ]}
        />
      </Section>
    </Showcase>
  ),
};
