import type { Meta, StoryObj } from '@storybook/react-vite';

import { Spinner } from '#/collaborative-editor/components/common/Spinner';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * `Spinner` is the shared loading spinner. It renders the `hero-arrow-path`
 * heroicon with Tailwind's `animate-spin`, and comes in three sizes. Colour is
 * controlled with a `text-*` class via `className`.
 */
const meta = {
  title: 'Components/Spinner',
  tags: ['core'],
  component: Spinner,
  parameters: { layout: 'centered' },
  args: { size: 'md' },
  argTypes: {
    size: { control: 'inline-radio', options: ['sm', 'md', 'lg'] },
  },
} satisfies Meta<typeof Spinner>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Sizes: Story = {
  render: () => (
    <Showcase>
      <Section title="Sizes">
        <Row>
          <Specimen label="sm">
            <Spinner size="sm" />
          </Specimen>
          <Specimen label="md">
            <Spinner size="md" />
          </Specimen>
          <Specimen label="lg">
            <Spinner size="lg" />
          </Specimen>
        </Row>
      </Section>
      <Section
        title="Colour"
        description="Tint the spinner by passing a text colour class."
      >
        <Row>
          <Specimen label="default">
            <Spinner size="lg" />
          </Specimen>
          <Specimen label="text-primary-500">
            <Spinner size="lg" className="text-primary-500" />
          </Specimen>
          <Specimen label="text-red-500">
            <Spinner size="lg" className="text-red-500" />
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
