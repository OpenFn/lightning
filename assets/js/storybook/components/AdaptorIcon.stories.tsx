import type { Meta, StoryObj } from '@storybook/react-vite';

import { AdaptorIcon } from '#/collaborative-editor/components/AdaptorIcon';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * Square adaptor icon (`js/collaborative-editor/components/AdaptorIcon.tsx`).
 * It looks up an icon image from a manifest fetched at runtime
 * (`/images/adaptors/adaptor_icons.json`). That manifest is not served in
 * Storybook, so the component renders its deterministic fallback: a gray tile
 * with the adaptor's first letter (or `?` when the name cannot be parsed).
 * Available in `sm`, `md`, and `lg` sizes.
 */
const meta = {
  title: 'Components/Adaptor Icon',
  tags: ['useful', 'bespoke'],
  component: AdaptorIcon,
  parameters: { layout: 'centered' },
  args: { name: '@openfn/language-salesforce@latest', size: 'md' },
  argTypes: {
    size: { control: 'inline-radio', options: ['sm', 'md', 'lg'] },
    name: { control: 'text' },
  },
} satisfies Meta<typeof AdaptorIcon>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Sizes: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Sizes"
        description="Fallback tile shown at each size (no manifest in Storybook)."
      >
        <Row>
          {(['sm', 'md', 'lg'] as const).map(size => (
            <Specimen key={size} label={size}>
              <AdaptorIcon name="@openfn/language-http@latest" size={size} />
            </Specimen>
          ))}
        </Row>
      </Section>

      <Section
        title="Fallback letters"
        description="The first letter is derived from the adaptor name; an unparseable name renders a question mark."
      >
        <Row>
          <Specimen label="salesforce">
            <AdaptorIcon name="@openfn/language-salesforce@latest" />
          </Specimen>
          <Specimen label="dhis2">
            <AdaptorIcon name="@openfn/language-dhis2@latest" />
          </Specimen>
          <Specimen label="unparseable">
            <AdaptorIcon name="not-an-adaptor" />
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
