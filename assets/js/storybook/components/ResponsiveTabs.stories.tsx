import type { Meta, StoryObj } from '@storybook/react-vite';
import type { SVGAttributes } from 'react';

import { Tabs } from '#/components/Tabs';
import type { TabSpec } from '#/components/Tabs';

import { Showcase, Section } from '../_shared/showcase';

/**
 * Responsive tab bar (`js/components/Tabs.tsx`). In a wide container it renders
 * pill-style tabs; below roughly `120px` per tab it collapses to a native
 * `<select>`. A `collapsedVertical` variant renders a narrow vertical rail.
 * Each tab takes an SVG component as its `icon`; the stories use small inline
 * placeholder icons. Selection is internal state, surfaced via
 * `onSelectionChange`.
 *
 * (Distinct from the collaborative-editor `Tabs`, which is a controlled
 * value/onChange switcher — see "Components/Tabs".)
 */
function DocIcon(props: SVGAttributes<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" {...props}>
      <path d="M4 3h8l4 4v10H4z" />
    </svg>
  );
}

function CodeIcon(props: SVGAttributes<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" {...props}>
      <path d="M7 5 3 10l4 5M13 5l4 5-4 5" />
    </svg>
  );
}

function GearIcon(props: SVGAttributes<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" {...props}>
      <circle cx="10" cy="10" r="4" />
    </svg>
  );
}

const OPTIONS: TabSpec[] = [
  { id: 'overview', label: 'Overview', icon: DocIcon },
  { id: 'editor', label: 'Editor', icon: CodeIcon },
  { id: 'settings', label: 'Settings', icon: GearIcon },
];

const meta = {
  title: 'Components/Tabs (Responsive)',
  component: Tabs,
  parameters: { layout: 'padded' },
  args: {
    options: OPTIONS,
    initialSelection: 'overview',
    collapsedVertical: false,
    onSelectionChange: () => {},
  },
} satisfies Meta<typeof Tabs>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {
  render: args => (
    <div className="w-[480px]">
      <Tabs {...args} />
    </div>
  ),
};

export const Layouts: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Wide (pill tabs)"
        description="Default layout when the container is wide enough for every tab."
      >
        <div className="w-[480px]">
          <Tabs options={OPTIONS} />
        </div>
      </Section>

      <Section
        title="Narrow (dropdown fallback)"
        description="Below ~120px per tab the bar collapses to a native select."
      >
        <div className="w-44">
          <Tabs options={OPTIONS} />
        </div>
      </Section>

      <Section
        title="Collapsed vertical"
        description="Compact vertical rail for collapsed side panels."
      >
        <div className="h-56">
          <Tabs options={OPTIONS} collapsedVertical />
        </div>
      </Section>
    </Showcase>
  ),
};
