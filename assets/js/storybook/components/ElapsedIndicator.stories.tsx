import type { Meta, StoryObj } from '@storybook/react-vite';

import { ElapsedIndicator } from '#/collaborative-editor/components/run-viewer/ElapsedIndicator';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * `ElapsedIndicator` shows how long a run took. Given both `startedAt` and
 * `finishedAt` it renders a fixed duration (ms / s / m); with only `startedAt`
 * it ticks live every second; with neither it shows "Not started".
 */
const meta = {
  title: 'Components/Elapsed Indicator',
  tags: ['useful', 'bespoke'],
  component: ElapsedIndicator,
  parameters: { layout: 'centered' },
  args: {
    startedAt: '2024-01-01T00:00:00.000Z',
    finishedAt: '2024-01-01T00:00:04.000Z',
  },
} satisfies Meta<typeof ElapsedIndicator>;

export default meta;

type Story = StoryObj<typeof meta>;

const START = '2024-01-01T00:00:00.000Z';

export const Playground: Story = {};

export const Examples: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Finished runs"
        description="A fixed duration is shown when both timestamps are present."
      >
        <Row>
          <Specimen label="milliseconds">
            <ElapsedIndicator
              startedAt={START}
              finishedAt="2024-01-01T00:00:00.420Z"
            />
          </Specimen>
          <Specimen label="seconds">
            <ElapsedIndicator
              startedAt={START}
              finishedAt="2024-01-01T00:00:04.000Z"
            />
          </Specimen>
          <Specimen label="minutes">
            <ElapsedIndicator
              startedAt={START}
              finishedAt="2024-01-01T00:03:30.000Z"
            />
          </Specimen>
        </Row>
      </Section>
      <Section
        title="Edge cases"
        description="A running indicator (no finish time) updates every second; with no start time it reads 'Not started'."
      >
        <Row>
          <Specimen label="running (live)">
            <ElapsedIndicator
              startedAt={new Date(Date.now() - 5000).toISOString()}
              finishedAt={null}
            />
          </Specimen>
          <Specimen label="not started">
            <ElapsedIndicator startedAt={null} finishedAt={null} />
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
