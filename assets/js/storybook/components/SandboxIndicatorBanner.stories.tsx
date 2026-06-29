import type { Meta, StoryObj } from '@storybook/react-vite';

import { SandboxIndicatorBanner } from '#/collaborative-editor/components/SandboxIndicatorBanner';

import { Showcase, Section } from '../_shared/showcase';

/**
 * Warning banner shown when editing a sandbox project
 * (`js/collaborative-editor/components/SandboxIndicatorBanner.tsx`). It renders
 * only when `parentProjectId` is set. The `full` variant (canvas overlay)
 * shows the long message; the `compact` variant (inspector panel) shows just
 * the sandbox name. Stories use `position="relative"` so the banner sits in
 * normal flow.
 */
const meta = {
  title: 'Components/Sandbox Indicator Banner',
  tags: ['useful'],
  component: SandboxIndicatorBanner,
  parameters: { layout: 'fullscreen' },
  args: {
    parentProjectId: 'root-project-id',
    parentProjectName: 'Production',
    projectName: 'qa-sandbox',
    position: 'relative',
    variant: 'full',
  },
  argTypes: {
    position: { control: 'inline-radio', options: ['absolute', 'relative'] },
    variant: { control: 'inline-radio', options: ['full', 'compact'] },
  },
} satisfies Meta<typeof SandboxIndicatorBanner>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Variants: Story = {
  render: () => (
    <Showcase>
      <Section
        title="full"
        description="Canvas overlay message naming the sandbox."
      >
        <SandboxIndicatorBanner
          parentProjectId="root-project-id"
          projectName="qa-sandbox"
          position="relative"
          variant="full"
        />
      </Section>

      <Section
        title="compact"
        description="Condensed label for the inspector panel."
      >
        <SandboxIndicatorBanner
          parentProjectId="root-project-id"
          projectName="qa-sandbox"
          position="relative"
          variant="compact"
        />
      </Section>
    </Showcase>
  ),
};
