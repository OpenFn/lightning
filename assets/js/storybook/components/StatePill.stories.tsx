import type { Meta, StoryObj } from '@storybook/react-vite';

import { StatePill } from '#/collaborative-editor/components/run-viewer/StatePill';
import { ALL_RUN_STATES } from '#/collaborative-editor/types/history';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * `StatePill` is the coloured run-state chip ported from the LiveView run
 * components. A few states are relabelled for display: `available` →
 * "Enqueued", `claimed` → "Starting", `started` → "Running".
 */
const meta = {
  title: 'Components/State Pill',
  tags: ['useful'],
  component: StatePill,
  parameters: { layout: 'centered' },
  args: { state: 'success' },
  argTypes: {
    state: { control: 'select', options: ALL_RUN_STATES },
  },
} satisfies Meta<typeof StatePill>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const AllStates: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Run states"
        description="Every state in ALL_RUN_STATES with its display label and chip colour."
      >
        <Row>
          {ALL_RUN_STATES.map(state => (
            <Specimen key={state} label={state}>
              <StatePill state={state} />
            </Specimen>
          ))}
        </Row>
      </Section>
    </Showcase>
  ),
};
