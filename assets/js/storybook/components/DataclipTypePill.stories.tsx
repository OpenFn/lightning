import type { Meta, StoryObj } from '@storybook/react-vite';

import DataclipTypePill from '#/manual-run-panel/DataclipTypePill';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * Color-coded pill that labels the source of a dataclip
 * (`js/manual-run-panel/DataclipTypePill.tsx`). Each of the four dataclip
 * types maps to a fixed color, and a `small` size variant is available for
 * dense lists.
 */
type DataclipType = 'step_result' | 'http_request' | 'global' | 'saved_input';

const TYPES: DataclipType[] = [
  'step_result',
  'http_request',
  'global',
  'saved_input',
];

const meta = {
  title: 'Components/Dataclip Type Pill',
  tags: ['useful'],
  component: DataclipTypePill,
  parameters: { layout: 'centered' },
  args: { type: 'saved_input', size: 'default' },
  argTypes: {
    type: { control: 'select', options: TYPES },
    size: { control: 'inline-radio', options: ['default', 'small'] },
  },
} satisfies Meta<typeof DataclipTypePill>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Types: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Types"
        description="One color per dataclip source type."
      >
        <Row>
          {TYPES.map(type => (
            <DataclipTypePill key={type} type={type} />
          ))}
        </Row>
      </Section>

      <Section title="Sizes">
        <Row>
          {(['default', 'small'] as const).map(size => (
            <Specimen key={size} label={size}>
              <DataclipTypePill type="step_result" size={size} />
            </Specimen>
          ))}
        </Row>
      </Section>
    </Showcase>
  ),
};
