import type { Meta, StoryObj } from '@storybook/react-vite';
import type { FC, SVGProps } from 'react';
import { useState } from 'react';

import { Tabs } from '#/collaborative-editor/components/Tabs';

import { Showcase, Section } from '../_shared/showcase';

/**
 * `Tabs` is a controlled tab switcher with two visual variants: `underline`
 * (the default, a bottom-border indicator) and `pills` (rounded pills inside a
 * grey container). Each option may carry an optional icon component.
 */
type View = 'input' | 'output' | 'logs';

const OPTIONS: { value: View; label: string }[] = [
  { value: 'input', label: 'Input' },
  { value: 'output', label: 'Output' },
  { value: 'logs', label: 'Logs' },
];

const noop = () => {};

const meta = {
  title: 'Components/Tabs',
  tags: ['core'],
  component: Tabs,
  parameters: { layout: 'centered' },
  args: { value: 'input', onChange: noop, options: OPTIONS },
} satisfies Meta<typeof Tabs>;

export default meta;

type Story = StoryObj<typeof meta>;

const CircleIcon: FC<SVGProps<SVGSVGElement>> = props => (
  <svg viewBox="0 0 20 20" fill="currentColor" {...props}>
    <circle cx="10" cy="10" r="7" />
  </svg>
);

const ICON_OPTIONS: { value: View; label: string; icon: typeof CircleIcon }[] =
  [
    { value: 'input', label: 'Input', icon: CircleIcon },
    { value: 'output', label: 'Output', icon: CircleIcon },
    { value: 'logs', label: 'Logs', icon: CircleIcon },
  ];

function ControlledTabs({
  variant,
  withIcons = false,
}: {
  variant: 'pills' | 'underline';
  withIcons?: boolean;
}) {
  const [value, setValue] = useState<View>('input');
  return (
    <Tabs
      value={value}
      onChange={setValue}
      options={withIcons ? ICON_OPTIONS : OPTIONS}
      variant={variant}
    />
  );
}

export const Underline: Story = {
  render: () => <ControlledTabs variant="underline" />,
};

export const Pills: Story = {
  render: () => (
    <div className="w-80">
      <ControlledTabs variant="pills" />
    </div>
  ),
};

export const Variants: Story = {
  render: () => (
    <Showcase>
      <Section title="Underline (default)">
        <ControlledTabs variant="underline" />
      </Section>
      <Section title="Underline with icons">
        <ControlledTabs variant="underline" withIcons />
      </Section>
      <Section title="Pills">
        <div className="w-80">
          <ControlledTabs variant="pills" />
        </div>
      </Section>
      <Section title="Pills with icons">
        <div className="w-80">
          <ControlledTabs variant="pills" withIcons />
        </div>
      </Section>
    </Showcase>
  ),
};
