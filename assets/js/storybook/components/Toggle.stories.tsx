import type { Meta, StoryObj } from '@storybook/react-vite';
import { useState } from 'react';

import { Toggle } from '#/collaborative-editor/components/Toggle';

import { Showcase, Section } from '../_shared/showcase';

/**
 * `Toggle` is the iOS-style switch with an associated label, matching the
 * LiveView toggle style. It is fully controlled: the parent owns `checked` and
 * updates it from `onChange`.
 */
const noop = () => {};

const meta = {
  title: 'Components/Toggle',
  tags: ['core'],
  component: Toggle,
  parameters: { layout: 'centered' },
  args: {
    id: 'toggle-playground',
    label: 'Enable feature',
    checked: false,
    disabled: false,
    onChange: noop,
  },
  argTypes: {
    onChange: { control: false },
  },
} satisfies Meta<typeof Toggle>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {
  render: function PlaygroundToggle(args) {
    const [checked, setChecked] = useState(args.checked);
    return <Toggle {...args} checked={checked} onChange={setChecked} />;
  },
};

export const States: Story = {
  render: () => (
    <Showcase>
      <Section title="States">
        <div className="flex flex-col gap-3">
          <Toggle
            id="toggle-off"
            label="Off"
            checked={false}
            onChange={noop}
          />
          <Toggle id="toggle-on" label="On" checked onChange={noop} />
          <Toggle
            id="toggle-disabled-off"
            label="Disabled (off)"
            checked={false}
            onChange={noop}
            disabled
          />
          <Toggle
            id="toggle-disabled-on"
            label="Disabled (on)"
            checked
            onChange={noop}
            disabled
          />
        </div>
      </Section>
    </Showcase>
  ),
};
