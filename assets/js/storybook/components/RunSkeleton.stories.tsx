import type { Meta, StoryObj } from '@storybook/react-vite';

import { RunSkeleton } from '#/collaborative-editor/components/run-viewer/RunSkeleton';

/**
 * `RunSkeleton` is the animated placeholder shown in the run viewer while run
 * detail loads. It takes no props and fills the height of its container.
 */
const meta = {
  title: 'Components/Run Skeleton',
  tags: ['useful', 'bespoke'],
  component: RunSkeleton,
  parameters: { layout: 'fullscreen' },
} satisfies Meta<typeof RunSkeleton>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Default: Story = {
  render: () => (
    <div className="h-96 w-80 border border-gray-200">
      <RunSkeleton />
    </div>
  ),
};
