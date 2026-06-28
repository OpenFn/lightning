import type { Meta, StoryObj } from '@storybook/react-vite';
import {
  ReactFlow,
  ReactFlowProvider,
  type Node as FlowNode,
  type NodeTypes,
} from '@xyflow/react';

import realNodeTypes from '#/workflow-diagram/nodes';

/**
 * The diagram's custom xyflow node renderers — the `job`, `trigger` and
 * `placeholder` components registered in `workflow-diagram/nodes`. Because they
 * read `NodeProps` and draw xyflow `Handle`s, each story mounts a real (static,
 * non-interactive) `<ReactFlow>` inside a fixed-size canvas and lets React Flow
 * inject the node props from the `data` we provide.
 *
 * - `Job` shows the adaptor name as its sublabel and the adaptor icon when the
 *   manifest is available (it is not served in Storybook, so the adaptor name
 *   stands in).
 * - `Trigger` switches its label/glyph on the trigger type (webhook, cron,
 *   kafka) and shows a padlock when authentication is required.
 * - `PlaceholderJob` is the inline "name your new step" editor; it grabs focus
 *   on mount, exactly as it does in the diagram.
 *
 * We reuse the diagram's own `nodeTypes` map verbatim. Those components are
 * typed loosely against React Flow's strict `NodeProps` (the production diagram
 * registers them the same way), so the map is widened through `unknown` at this
 * single boundary — runtime behaviour is unchanged.
 */
const nodeTypes = realNodeTypes as unknown as NodeTypes;

// --- canvas helper ---------------------------------------------------------

function DiagramCanvas({ nodes }: { nodes: FlowNode[] }) {
  return (
    <div style={{ width: 480, height: 320 }}>
      <ReactFlowProvider>
        <ReactFlow
          nodes={nodes}
          edges={[]}
          nodeTypes={nodeTypes}
          fitView
          fitViewOptions={{ padding: 0.4 }}
          minZoom={0.2}
          maxZoom={1}
          nodesDraggable={false}
          nodesConnectable={false}
          elementsSelectable={false}
          panOnDrag={false}
          zoomOnScroll={false}
          proOptions={{ hideAttribution: true }}
        />
      </ReactFlowProvider>
    </div>
  );
}

const jobNode = (
  id: string,
  position: { x: number; y: number },
  data: { name: string; adaptor: string; allowPlaceholder: boolean }
): FlowNode => ({ id, type: 'job', position, data });

const triggerNode = (
  id: string,
  position: { x: number; y: number },
  data: Record<string, unknown>
): FlowNode => ({ id, type: 'trigger', position, data });

const meta = {
  title: 'Components/Workflow Diagram/Nodes',
  parameters: { layout: 'centered' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const JobStory: Story = {
  name: 'Job',
  render: () => (
    <DiagramCanvas
      nodes={[
        jobNode(
          'job-1',
          { x: 0, y: 0 },
          {
            name: 'Transform data',
            adaptor: '@openfn/language-http@latest',
            allowPlaceholder: false,
          }
        ),
      ]}
    />
  ),
};

export const JobSelected: Story = {
  render: () => (
    <DiagramCanvas
      nodes={[
        {
          ...jobNode(
            'job-1',
            { x: 0, y: 0 },
            {
              name: 'Upsert patients',
              adaptor: '@openfn/language-dhis2@latest',
              allowPlaceholder: false,
            }
          ),
          selected: true,
        },
      ]}
    />
  ),
};

export const Triggers: Story = {
  render: () => (
    <DiagramCanvas
      nodes={[
        triggerNode(
          'trigger-webhook',
          { x: 0, y: 0 },
          {
            id: 'trigger-webhook',
            name: 'webhook',
            workflow_id: 'wf-1',
            enabled: true,
            type: 'webhook',
            has_auth_method: true,
            trigger: { type: 'webhook', enabled: true, has_auth_method: true },
          }
        ),
        triggerNode(
          'trigger-cron',
          { x: 0, y: 200 },
          {
            id: 'trigger-cron',
            name: 'cron',
            workflow_id: 'wf-1',
            enabled: true,
            type: 'cron',
            cron_expression: '0 9 * * 1',
            trigger: {
              type: 'cron',
              enabled: true,
              cron_expression: '0 9 * * 1',
            },
          }
        ),
        triggerNode(
          'trigger-kafka',
          { x: 0, y: 400 },
          {
            id: 'trigger-kafka',
            name: 'kafka',
            workflow_id: 'wf-1',
            enabled: true,
            type: 'kafka',
            has_auth_method: false,
            trigger: { type: 'kafka', enabled: true, has_auth_method: false },
          }
        ),
      ]}
    />
  ),
};

export const Placeholder: Story = {
  render: () => (
    <DiagramCanvas
      nodes={[
        {
          id: 'placeholder-1',
          type: 'placeholder',
          position: { x: 0, y: 0 },
          data: {},
        },
      ]}
    />
  ),
};
