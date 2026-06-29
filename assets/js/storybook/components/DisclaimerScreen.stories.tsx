import type { Meta, StoryObj } from '@storybook/react-vite';

import { DisclaimerScreen } from '#/collaborative-editor/components/DisclaimerScreen';

/**
 * Full-screen onboarding disclaimer shown before first use of the AI Assistant
 * (`js/collaborative-editor/components/DisclaimerScreen.tsx`). The user must
 * click "Get started" (`onAccept`) to proceed. The `disabled` prop greys out
 * the button while acknowledgement is in flight.
 */
const meta = {
  title: 'Components/Disclaimer Screen',
  tags: ['useful'],
  component: DisclaimerScreen,
  parameters: { layout: 'fullscreen' },
  args: {
    onAccept: () => {},
    disabled: false,
  },
} satisfies Meta<typeof DisclaimerScreen>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Default: Story = {};

export const Disabled: Story = {
  args: { disabled: true },
};
