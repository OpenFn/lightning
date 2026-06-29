import type { Meta, StoryObj } from '@storybook/react-vite';
import type { MiniMapNodeProps } from '@xyflow/react';

import MiniMapNode from '#/workflow-diagram/components/MiniMapNode';

import { Showcase, Section, Row, Specimen } from '../../_shared/showcase';

/**
 * `MiniMapNode` renders a single node inside the diagram's minimap. Triggers are
 * drawn as a circle with a globe (webhook) or clock (cron/kafka) glyph; jobs are
 * drawn as a rounded square that shows the adaptor icon when the manifest has
 * loaded, falling back to a plain square otherwise.
 *
 * It accepts the xyflow `MiniMapNodeProps` plus optional `jobs`/`triggers`
 * arrays. We pass those explicitly here (the Collaborative Editor pattern) so
 * the renderer does not depend on the global workflow store. Each specimen
 * wraps the emitted `<g>` in its own `<svg>` viewport.
 */
type Job = { id: string; adaptor?: string };
type Trigger = { id: string; type: 'webhook' | 'cron' | 'kafka' };

const JOBS: Job[] = [
  { id: 'job-http', adaptor: '@openfn/language-http@latest' },
];
const TRIGGERS: Trigger[] = [
  { id: 'trigger-webhook', type: 'webhook' },
  { id: 'trigger-cron', type: 'cron' },
];

// The minimap positions nodes in flow coordinates; the renderer offsets drawing
// from x/y, so a small viewBox origin keeps each specimen centred.
const baseProps = {
  x: 10,
  y: 10,
  width: 120,
  height: 120,
  borderRadius: 20,
  className: '',
  shapeRendering: 'geometricPrecision',
  selected: false,
} satisfies Omit<MiniMapNodeProps, 'id'>;

function MiniMapStage({
  id,
  jobs,
  triggers,
}: {
  id: string;
  jobs: Job[];
  triggers: Trigger[];
}) {
  return (
    <svg width={140} height={140} viewBox="0 0 140 140">
      <MiniMapNode {...baseProps} id={id} jobs={jobs} triggers={triggers} />
    </svg>
  );
}

const meta = {
  title: 'Editor/Diagram/MiniMapNode',
  tags: ['useful'],
  parameters: { layout: 'centered' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Nodes: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Minimap nodes"
        description="A webhook trigger, a cron trigger and a job. The job falls back to a plain square here because the adaptor-icon manifest is not served in Storybook."
      >
        <Row>
          <Specimen label="webhook trigger">
            <MiniMapStage
              id="trigger-webhook"
              jobs={JOBS}
              triggers={TRIGGERS}
            />
          </Specimen>
          <Specimen label="cron trigger">
            <MiniMapStage id="trigger-cron" jobs={JOBS} triggers={TRIGGERS} />
          </Specimen>
          <Specimen label="job">
            <MiniMapStage id="job-http" jobs={JOBS} triggers={TRIGGERS} />
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
