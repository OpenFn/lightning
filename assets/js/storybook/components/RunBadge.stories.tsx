import type { Meta, StoryObj } from '@storybook/react-vite';

import { RunBadge } from '#/collaborative-editor/components/common/RunBadge';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * `RunBadge` wraps {@link Badge} to show a selected run as a compact pill. The
 * run UUID is truncated to its first seven characters and a close button
 * deselects the run.
 */
const noop = () => {};

const meta = {
  title: 'Components/Run Badge',
  component: RunBadge,
  parameters: { layout: 'centered' },
  args: {
    runId: '8a3f0c12-9b1e-4d77-a8c3-1f2e3d4c5b6a',
    variant: 'default',
    onClose: noop,
  },
  argTypes: {
    variant: { control: 'inline-radio', options: ['default', 'warning'] },
    onClose: { control: false },
  },
} satisfies Meta<typeof RunBadge>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Variants: Story = {
  render: () => (
    <Showcase>
      <Section title="Variants">
        <Row>
          <Specimen label="default">
            <RunBadge
              runId="8a3f0c12-9b1e-4d77-a8c3-1f2e3d4c5b6a"
              variant="default"
              onClose={noop}
            />
          </Specimen>
          <Specimen label="warning">
            <RunBadge
              runId="c5d6e7f8-0a1b-4c2d-9e3f-4a5b6c7d8e9f"
              variant="warning"
              onClose={noop}
            />
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
