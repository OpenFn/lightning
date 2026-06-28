import type { Meta, StoryObj } from '@storybook/react-vite';

import { LoadingIndicator } from '#/collaborative-editor/components/common/LoadingIndicator';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * `LoadingIndicator` pairs a {@link Spinner} with a text label. It is used for
 * inline loading states such as Monaco type definitions or workflow loading.
 */
const meta = {
  title: 'Components/Loading Indicator',
  component: LoadingIndicator,
  parameters: { layout: 'centered' },
  args: { text: 'Loading' },
} satisfies Meta<typeof LoadingIndicator>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Examples: Story = {
  render: () => (
    <Showcase>
      <Section title="Messages">
        <Row>
          <Specimen label="default">
            <LoadingIndicator />
          </Specimen>
          <Specimen label="custom text">
            <LoadingIndicator text="Loading types" />
          </Specimen>
          <Specimen label="custom text">
            <LoadingIndicator text="Loading workflow" />
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
