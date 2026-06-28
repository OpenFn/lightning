import type { Meta, StoryObj } from '@storybook/react-vite';

import Shape from '#/workflow-diagram/components/Shape';
import { nodeIconStyles } from '#/workflow-diagram/styles';

import { Showcase, Section, Row, Specimen } from '../../_shared/showcase';

/**
 * `Shape` is the bare SVG primitive drawn behind every workflow node: a rounded
 * `rect` for jobs and an `ellipse` (`circle`) for triggers. It takes raw
 * `width`/`height`/`strokeWidth` plus a `styles` object of SVG presentation
 * attributes (`stroke`, `fill`). The diagram derives those from
 * `nodeIconStyles`, which we reuse here so the specimens match production
 * colours.
 *
 * It renders SVG elements, so every specimen wraps it in an `<svg>` sized to fit
 * the shape plus its stroke offset.
 */
const SIZE = 100;
const STROKE = 2;

function ShapeCanvas({ children }: { children: React.ReactNode }) {
  return (
    <svg
      width={SIZE + STROKE * 2}
      height={SIZE + STROKE * 2}
      style={{ overflow: 'visible' }}
    >
      {children}
    </svg>
  );
}

const meta = {
  title: 'Editor/Diagram/Shape',
  component: Shape,
  parameters: { layout: 'centered' },
  args: {
    shape: 'rect',
    width: SIZE,
    height: SIZE,
    strokeWidth: STROKE,
    styles: nodeIconStyles().style,
  },
  argTypes: {
    shape: { control: 'inline-radio', options: ['rect', 'circle'] },
    width: { control: { type: 'range', min: 40, max: 160, step: 4 } },
    height: { control: { type: 'range', min: 40, max: 160, step: 4 } },
    strokeWidth: { control: { type: 'range', min: 1, max: 8, step: 1 } },
    styles: { control: false },
  },
  render: args => (
    <ShapeCanvas>
      <Shape {...args} />
    </ShapeCanvas>
  ),
} satisfies Meta<typeof Shape>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Shapes: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Shapes"
        description="Jobs are drawn as a rounded rectangle; triggers as a circle."
      >
        <Row>
          {(['rect', 'circle'] as const).map(shape => (
            <Specimen key={shape} label={shape}>
              <ShapeCanvas>
                <Shape
                  shape={shape}
                  width={SIZE}
                  height={SIZE}
                  strokeWidth={STROKE}
                  styles={nodeIconStyles().style}
                />
              </ShapeCanvas>
            </Specimen>
          ))}
        </Row>
      </Section>
    </Showcase>
  ),
};

export const States: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Run states"
        description="`nodeIconStyles` tints the stroke and fill by selection, error and run outcome. These are the fills the diagram applies to a job node."
      >
        <Row>
          {(
            [
              { label: 'default', style: nodeIconStyles().style },
              { label: 'selected', style: nodeIconStyles(true).style },
              { label: 'errors', style: nodeIconStyles(false, true).style },
              {
                label: 'success',
                style: nodeIconStyles(false, false, 'success').style,
              },
              {
                label: 'fail',
                style: nodeIconStyles(false, false, 'fail').style,
              },
              {
                label: 'crash',
                style: nodeIconStyles(false, false, 'crash').style,
              },
              {
                label: 'running',
                style: nodeIconStyles(false, false, 'running').style,
              },
            ] as const
          ).map(({ label, style }) => (
            <Specimen key={label} label={label}>
              <ShapeCanvas>
                <Shape
                  shape="rect"
                  width={SIZE}
                  height={SIZE}
                  strokeWidth={STROKE}
                  styles={style}
                />
              </ShapeCanvas>
            </Specimen>
          ))}
        </Row>
      </Section>
    </Showcase>
  ),
};
