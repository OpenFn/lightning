import type { Meta, StoryObj } from '@storybook/react-vite';
import { useState } from 'react';

import { Switch } from '#/collaborative-editor/components/inputs/Switch';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * `Switch` is a Headless UI based toggle with check / cross glyphs inside the
 * knob. It is fully controlled and has no associated label, so it is typically
 * paired with adjacent text by the caller.
 */
const noop = () => {};

const meta = {
  title: 'Components/Switch',
  tags: ['redundant'],
  component: Switch,
  parameters: { layout: 'centered' },
  args: { checked: false, disabled: false, onChange: noop },
  argTypes: {
    onChange: { control: false },
    className: { control: false },
  },
} satisfies Meta<typeof Switch>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {
  render: function PlaygroundSwitch(args) {
    const [checked, setChecked] = useState(args.checked);
    return <Switch {...args} checked={checked} onChange={setChecked} />;
  },
};

export const States: Story = {
  render: () => (
    <Showcase>
      <Section title="States">
        <Row>
          <Specimen label="off">
            <Switch checked={false} onChange={noop} />
          </Specimen>
          <Specimen label="on">
            <Switch checked onChange={noop} />
          </Specimen>
          <Specimen label="disabled (off)">
            <Switch checked={false} onChange={noop} disabled />
          </Specimen>
          <Specimen label="disabled (on)">
            <Switch checked onChange={noop} disabled />
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
