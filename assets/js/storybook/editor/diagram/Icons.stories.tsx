import * as RadixTooltip from '@radix-ui/react-tooltip';
import type { Meta, StoryObj } from '@storybook/react-vite';

import { renderIcon } from '#/workflow-diagram/components/RunIcons';
import {
  kafkaIcon,
  lockClosedIcon,
} from '#/workflow-diagram/components/trigger-icons';

import { Showcase, Section, Row, Specimen } from '../../_shared/showcase';

/**
 * Icon overlays used by the workflow diagram.
 *
 * `renderIcon` (from `RunIcons`) draws the small status badge pinned to the
 * corner of a job node while a run is in progress or after it finishes. Each
 * state maps to a heroicon and colour; an optional tooltip wraps it. The
 * `trigger-icons` module exports two hand-built SVGs — a padlock badge shown on
 * triggers that require authentication, and the Kafka glyph for Kafka triggers.
 */
const RUN_STATES = [
  'pending',
  'running',
  'success',
  'fail',
  'crash',
  'cancel',
  'shield',
  'clock',
  'circle_ex',
  'triangle_ex',
] as const;

function IconGallery() {
  return (
    <RadixTooltip.Provider>
      <Showcase className="min-w-[640px]">
        <Section
          title="Run state badges"
          description="`renderIcon(state)` — the badge overlaid on a job node to show its step status during and after a run."
        >
          <Row>
            {RUN_STATES.map(state => (
              <Specimen key={state} label={state}>
                {renderIcon(state)}
              </Specimen>
            ))}
          </Row>
        </Section>

        <Section
          title="With tooltip"
          description="Passing a `tooltip` wraps the badge so hovering reveals the step message."
        >
          <Row>
            <Specimen label="success">
              {renderIcon('success', { tooltip: 'Step completed successfully' })}
            </Specimen>
            <Specimen label="fail">
              {renderIcon('fail', { tooltip: 'RuntimeError' })}
            </Specimen>
          </Row>
        </Section>

        <Section
          title="Trigger glyphs"
          description="Standalone SVGs from `trigger-icons`, rendered at their native size."
        >
          <Row>
            <Specimen label="lockClosedIcon">
              <div className="h-10 w-10">{lockClosedIcon}</div>
            </Specimen>
            <Specimen label="kafkaIcon">
              <div className="h-10 w-10 text-gray-500">{kafkaIcon}</div>
            </Specimen>
          </Row>
        </Section>
      </Showcase>
    </RadixTooltip.Provider>
  );
}

const meta = {
  title: 'Editor/Diagram/Icons',
  tags: ['useful'],
  component: IconGallery,
  parameters: { layout: 'fullscreen' },
} satisfies Meta<typeof IconGallery>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Gallery: Story = {};
