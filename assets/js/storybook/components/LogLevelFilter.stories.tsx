import type { Meta, StoryObj } from '@storybook/react-vite';
import { useState } from 'react';

import { LogLevelFilter } from '#/collaborative-editor/components/run-viewer/LogLevelFilter';

import { Showcase, Section } from '../_shared/showcase';

/**
 * `LogLevelFilter` is the dropdown used to filter run logs by minimum severity.
 * It is controlled via `selectedLevel` / `onLevelChange` and manages its own
 * open state, closing on outside click. The menu is dark, so it is shown here
 * on a dark surface like its real run-viewer toolbar.
 */
type LogLevel = 'debug' | 'info' | 'warn' | 'error';

const noop = () => {};

const meta = {
  title: 'Components/Log Level Filter',
  tags: ['useful', 'bespoke'],
  component: LogLevelFilter,
  parameters: { layout: 'centered' },
  args: { selectedLevel: 'info', onLevelChange: noop },
} satisfies Meta<typeof LogLevelFilter>;

export default meta;

type Story = StoryObj<typeof meta>;

function ControlledFilter() {
  const [level, setLevel] = useState<LogLevel>('info');
  return <LogLevelFilter selectedLevel={level} onLevelChange={setLevel} />;
}

export const Default: Story = {
  render: () => (
    <div className="w-40 rounded-md bg-slate-700 p-3 text-white">
      <ControlledFilter />
    </div>
  ),
};

export const InToolbar: Story = {
  render: () => (
    <Showcase>
      <Section
        title="On a dark toolbar"
        description="Click the control to open the level menu."
      >
        <div className="flex w-64 items-center justify-end rounded-md bg-slate-700 px-3 py-2 text-white">
          <ControlledFilter />
        </div>
      </Section>
    </Showcase>
  ),
};
