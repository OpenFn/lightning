import type { Meta, StoryObj } from '@storybook/react-vite';

import ErrorMessage from '#/workflow-diagram/components/ErrorMessage';

import { Showcase, Section } from '../../_shared/showcase';

/**
 * `ErrorMessage` is the small red, two-line-clamped validation line shown under
 * a node label (and reused for drop-target errors). It pairs an exclamation
 * heroicon with its children, falling back to a generic message when given
 * none.
 */
const meta = {
  title: 'Editor/Diagram/ErrorMessage',
  tags: ['useful', 'bespoke'],
  component: ErrorMessage,
  parameters: { layout: 'centered' },
  args: { children: 'Adaptor is required' },
  render: args => (
    <div className="w-72">
      <ErrorMessage {...args} />
    </div>
  ),
} satisfies Meta<typeof ErrorMessage>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Variants: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Messages"
        description="A custom message, the default fallback, and a long message clamped to two lines."
      >
        <div className="flex w-72 flex-col gap-3">
          <ErrorMessage>Adaptor is required</ErrorMessage>
          <ErrorMessage />
          <ErrorMessage>
            This step failed because the credential could not be decrypted and
            the request timed out after several retries.
          </ErrorMessage>
        </div>
      </Section>
    </Showcase>
  ),
};
