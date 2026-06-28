import type { Meta, StoryObj } from '@storybook/react-vite';

import { CollaborativeEditorPromoBanner } from '#/workflow-diagram/CollaborativeEditorPromoBanner';

/**
 * Promotional banner on the legacy workflow canvas nudging users toward the new
 * collaborative editor
 * (`js/workflow-diagram/CollaborativeEditorPromoBanner.tsx`). It is positioned
 * absolutely at the bottom of its container; the wrapper below gives it a
 * canvas-like backdrop to anchor against. Clicking the message fires
 * `pushEvent('switch_to_collab_editor')`, stubbed here with a no-op.
 */
const meta = {
  title: 'Components/Collaborative Editor Promo Banner',
  component: CollaborativeEditorPromoBanner,
  parameters: { layout: 'fullscreen' },
  args: {
    pushEvent: () => {},
  },
  decorators: [
    Story => (
      <div className="relative h-64 bg-slate-50">
        <Story />
      </div>
    ),
  ],
} satisfies Meta<typeof CollaborativeEditorPromoBanner>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Default: Story = {};
