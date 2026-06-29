import type { Meta, StoryObj } from '@storybook/react-vite';

import { StepIcon } from '#/collaborative-editor/components/run-viewer/StepIcon';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * `StepIcon` maps a run step's `exitReason` (and, for kills, its `errorType`)
 * to a coloured heroicon. It mirrors `LightningWeb.RunLive.Components.step_icon/1`.
 * A null exit reason renders the neutral "pending" icon.
 */
const meta = {
  title: 'Components/Step Icon',
  tags: ['useful'],
  component: StepIcon,
  parameters: { layout: 'centered' },
  args: { exitReason: 'success', errorType: null },
} satisfies Meta<typeof StepIcon>;

export default meta;

type Story = StoryObj<typeof meta>;

interface Case {
  label: string;
  exitReason: string | null;
  errorType: string | null;
}

const CASES: Case[] = [
  { label: 'pending', exitReason: null, errorType: null },
  { label: 'success', exitReason: 'success', errorType: null },
  { label: 'fail', exitReason: 'fail', errorType: null },
  { label: 'crash', exitReason: 'crash', errorType: null },
  { label: 'cancel', exitReason: 'cancel', errorType: null },
  { label: 'kill · Security', exitReason: 'kill', errorType: 'SecurityError' },
  { label: 'kill · Import', exitReason: 'kill', errorType: 'ImportError' },
  { label: 'kill · Timeout', exitReason: 'kill', errorType: 'TimeoutError' },
  { label: 'kill · OOM', exitReason: 'kill', errorType: 'OOMError' },
  {
    label: 'kill · StateTooLarge',
    exitReason: 'kill',
    errorType: 'StateTooLargeError',
  },
  { label: 'exception', exitReason: 'exception', errorType: null },
  { label: 'lost', exitReason: 'lost', errorType: null },
];

export const Playground: Story = {};

export const AllStates: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Exit reasons"
        description="Icon and colour for each step exit reason and kill error type."
      >
        <Row>
          {CASES.map(c => (
            <Specimen key={c.label} label={c.label}>
              <StepIcon exitReason={c.exitReason} errorType={c.errorType} />
            </Specimen>
          ))}
        </Row>
      </Section>
    </Showcase>
  ),
};
