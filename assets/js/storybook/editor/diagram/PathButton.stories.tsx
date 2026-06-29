import type { Meta, StoryObj } from '@storybook/react-vite';
import { ReactFlowProvider } from '@xyflow/react';

import PathButton from '#/workflow-diagram/components/PathButton';

import { Showcase, Section, Row, Specimen } from '../../_shared/showcase';

/**
 * `PathButton` is the small indigo "+" pill that appears on a job node's
 * toolbar to start a new downstream connection. It is implemented as a styled
 * xyflow `Handle`, so it must be rendered inside a `ReactFlowProvider`; here we
 * also give it `position: static` to lift it out of the absolute positioning a
 * real node would supply.
 */
function PathButtonStage({ children }: { children: React.ReactNode }) {
  return (
    <ReactFlowProvider>
      <div className="relative inline-flex" style={{ position: 'static' }}>
        {children}
      </div>
    </ReactFlowProvider>
  );
}

const meta = {
  title: 'Editor/Diagram/PathButton',
  tags: ['useful', 'bespoke'],
  component: PathButton,
  parameters: { layout: 'centered' },
  args: { id: 'node-connector' },
  render: args => (
    <PathButtonStage>
      <PathButton {...args}>
        <span className="hero-plus pointer-events-none h-4 w-4" />
      </PathButton>
    </PathButtonStage>
  ),
} satisfies Meta<typeof PathButton>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Examples: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Contents"
        description="The button renders whatever children it is given — the diagram uses a plus glyph."
      >
        <Row>
          <Specimen label="plus icon">
            <PathButtonStage>
              <PathButton id="connector-plus">
                <span className="hero-plus pointer-events-none h-4 w-4" />
              </PathButton>
            </PathButtonStage>
          </Specimen>
          <Specimen label="text">
            <PathButtonStage>
              <PathButton id="connector-text">Add step</PathButton>
            </PathButtonStage>
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
