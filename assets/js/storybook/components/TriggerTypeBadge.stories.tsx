import type { Meta, StoryObj } from '@storybook/react-vite';

import { TriggerTypeBadge } from '#/collaborative-editor/components/inspector/trigger/TriggerTypeBadge';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * `TriggerTypeBadge` is the small green pill identifying a workflow trigger's
 * type. Each type pairs a heroicon with a label: webhook → globe, cron →
 * clock ("Schedule / Cron"), kafka → queue list.
 */
const meta = {
  title: 'Components/Trigger Type Badge',
  tags: ['useful'],
  component: TriggerTypeBadge,
  parameters: { layout: 'centered' },
  args: { type: 'webhook' },
  argTypes: {
    type: { control: 'inline-radio', options: ['webhook', 'cron', 'kafka'] },
  },
} satisfies Meta<typeof TriggerTypeBadge>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Types: Story = {
  render: () => (
    <Showcase>
      <Section title="Trigger types">
        <Row>
          <Specimen label="webhook">
            <TriggerTypeBadge type="webhook" />
          </Specimen>
          <Specimen label="cron">
            <TriggerTypeBadge type="cron" />
          </Specimen>
          <Specimen label="kafka">
            <TriggerTypeBadge type="kafka" />
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
