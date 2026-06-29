import type { Meta, StoryObj } from '@storybook/react-vite';

import Badge from '#/collaborative-editor/components/common/Badge';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * `Badge` is the small pill used throughout the collaborative editor for
 * compact, dismissible labels. It supports a `default` (blue) and `warning`
 * (yellow) variant, and renders a heroicon close button when `onClose` is set.
 */
const meta = {
  title: 'Components/Badge',
  tags: ['core'],
  component: Badge,
  parameters: { layout: 'centered' },
  args: { variant: 'default', children: 'Badge' },
  argTypes: {
    variant: { control: 'inline-radio', options: ['default', 'warning'] },
    onClose: { control: false },
  },
} satisfies Meta<typeof Badge>;

export default meta;

type Story = StoryObj<typeof meta>;

const noop = () => {};

export const Playground: Story = {};

export const Variants: Story = {
  render: () => (
    <Showcase>
      <Section title="Variants">
        <Row>
          <Specimen label="default">
            <Badge variant="default">Default</Badge>
          </Specimen>
          <Specimen label="warning">
            <Badge variant="warning">Warning</Badge>
          </Specimen>
        </Row>
      </Section>
      <Section
        title="Dismissible"
        description="Passing onClose renders a close button with an accessible label."
      >
        <Row>
          <Specimen label="default">
            <Badge variant="default" onClose={noop}>
              Run abc1234
            </Badge>
          </Specimen>
          <Specimen label="warning">
            <Badge variant="warning" onClose={noop}>
              Unsaved changes
            </Badge>
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
