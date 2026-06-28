import type { Meta, StoryObj } from '@storybook/react-vite';

import { Tooltip } from '#/components/Tooltip';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * Accessible tooltip built on Radix UI primitives
 * (`js/components/Tooltip.tsx`). It renders its own provider/portal, so it
 * works standalone. Hover or focus the trigger to reveal the dark bubble; the
 * `side` and `align` props position it around the trigger.
 */
const triggerClasses =
  'rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white';

const SIDES = ['top', 'right', 'bottom', 'left'] as const;
const ALIGNS = ['start', 'center', 'end'] as const;

const meta = {
  title: 'Components/Tooltip',
  component: Tooltip,
  parameters: { layout: 'centered' },
  args: {
    content: 'Save changes',
    side: 'bottom',
    align: 'center',
    delayDuration: 200,
    children: (
      <button type="button" className={triggerClasses}>
        Hover me
      </button>
    ),
  },
  argTypes: {
    side: { control: 'inline-radio', options: SIDES },
    align: { control: 'inline-radio', options: ALIGNS },
    content: { control: 'text' },
  },
} satisfies Meta<typeof Tooltip>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Sides: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Sides"
        description="Hover or focus a trigger to reveal its tooltip on the chosen side."
      >
        <Row className="gap-10">
          {SIDES.map(side => (
            <Specimen key={side} label={side}>
              <Tooltip content={`Positioned ${side}`} side={side}>
                <button type="button" className={triggerClasses}>
                  {side}
                </button>
              </Tooltip>
            </Specimen>
          ))}
        </Row>
      </Section>
    </Showcase>
  ),
};

export const RichContent: Story = {
  args: {
    content: (
      <span>
        Run workflow <kbd>⌘</kbd> <kbd>Enter</kbd>
      </span>
    ),
  },
};
