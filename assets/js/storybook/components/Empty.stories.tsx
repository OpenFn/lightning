import type { Meta, StoryObj } from '@storybook/react-vite';

import Empty from '#/metadata-explorer/Empty';

/**
 * Placeholder shown in the metadata explorer when an adaptor returns no
 * metadata (`js/metadata-explorer/Empty.tsx`). Names the adaptor and explains
 * that magic functions are not yet supported for it.
 */
const meta = {
  title: 'Components/Metadata Explorer Empty',
  tags: ['useful', 'bespoke'],
  component: Empty,
  parameters: { layout: 'centered' },
  args: { adaptor: '@openfn/language-http' },
  argTypes: { adaptor: { control: 'text' } },
} satisfies Meta<typeof Empty>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Salesforce: Story = {
  args: { adaptor: '@openfn/language-salesforce' },
};
