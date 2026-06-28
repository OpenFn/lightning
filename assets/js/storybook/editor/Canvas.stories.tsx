import type { Meta, StoryObj } from '@storybook/react-vite';
import {
  Background,
  Controls,
  MiniMap,
  ReactFlow,
  ReactFlowProvider,
  type Edge as FlowEdge,
  type EdgeTypes,
  type Node as FlowNode,
  type NodeTypes,
} from '@xyflow/react';

import { Button } from '#/collaborative-editor/components/Button';
import { InspectorFooter } from '#/collaborative-editor/components/inspector/InspectorFooter';
import { InspectorLayout } from '#/collaborative-editor/components/inspector/InspectorLayout';
import { createEmptyRunInfo } from '#/collaborative-editor/utils/runStepsTransformer';
import MiniMapNode from '#/workflow-diagram/components/MiniMapNode';
import realEdgeTypes from '#/workflow-diagram/edges';
import realNodeTypes from '#/workflow-diagram/nodes';
import fromWorkflow from '#/workflow-diagram/util/from-workflow';

/**
 * Composite view of the *latest* (collaborative) workflow editor canvas.
 *
 * The diagram is built from the REAL editor code: the workflow is run through
 * `workflow-diagram/util/from-workflow` (the same transform the collaborative
 * editor uses) and rendered by the real `nodeTypes`/`edgeTypes` inside
 * `<ReactFlow>` — so the trigger/job nodes, the bezier connectors and the
 * condition badges (∞ / ✓ / X) are produced by production code. The inspector
 * uses the real `InspectorLayout`, `InspectorFooter` and `Button` components.
 *
 * Only two things are stand-ins, both because they require the live runtime
 * that isn't present in Storybook:
 *  - adaptor icons resolve from a server manifest, so the job nodes fall back
 *    to the adaptor name (their real no-icon behaviour);
 *  - the `JobForm` body is bound to the Y.Doc / credential / adaptor stores, so
 *    its fields (Job Name, Adaptor + Connect) are reproduced from its source.
 */
type WorkflowInput = Parameters<typeof fromWorkflow>[0];
type PositionsInput = Parameters<typeof fromWorkflow>[1];

const workflow = {
  id: 'wf-1',
  name: 'Patient sync',
  jobs: [
    {
      id: 'j1',
      name: 'adfasdfas',
      adaptor: '@openfn/language-googlesheets@latest',
      body: '',
    },
    {
      id: 'j2',
      name: 'compare data from sheets',
      adaptor: '@openfn/language-salesforce@latest',
      body: '',
    },
  ],
  triggers: [{ id: 't1', type: 'webhook', enabled: true }],
  edges: [
    {
      id: 'e1',
      source_trigger_id: 't1',
      target_job_id: 'j1',
      condition_type: 'always',
      enabled: true,
    },
    {
      id: 'e2',
      source_job_id: 'j1',
      target_job_id: 'j2',
      condition_type: 'on_job_success',
      enabled: true,
    },
  ],
} as unknown as WorkflowInput;

const positions: PositionsInput = {
  t1: { x: 280, y: 0 },
  j1: { x: 280, y: 200 },
  j2: { x: 280, y: 400 },
};

// Real editor transform → real ReactFlow model (nodes, edges, condition badges).
const model = fromWorkflow(
  workflow,
  positions,
  { nodes: [], edges: [] },
  createEmptyRunInfo(),
  'j1'
);
const nodes = model.nodes as unknown as FlowNode[];
const edges = model.edges as unknown as FlowEdge[];

// The diagram registers these loosely-typed against React Flow's strict prop
// types (production does the same), so widen through `unknown` at the boundary.
const nodeTypes = realNodeTypes as unknown as NodeTypes;
const edgeTypes = realEdgeTypes as unknown as EdgeTypes;

const INPUT_CLASSES =
  'block w-full rounded-md border-gray-300 text-sm text-gray-900 shadow-xs focus:border-primary-500 focus:ring-primary-500';

/**
 * Body of the job inspector, reproduced from
 * collaborative-editor/components/inspector/JobForm.tsx (which is bound to the
 * editor stores and can't render standalone).
 */
function JobFormBody() {
  return (
    <div className="space-y-4 p-6">
      <div>
        <label
          htmlFor="job-name"
          className="mb-2 block text-sm font-medium text-gray-700"
        >
          Job Name
        </label>
        <input
          id="job-name"
          type="text"
          defaultValue="adfasdfas"
          className={INPUT_CLASSES}
        />
      </div>
      <div>
        <span className="mb-2 flex items-center gap-1 text-sm font-medium text-gray-700">
          Adaptor
          <span className="hero-information-circle h-4 w-4 text-gray-400" />
        </span>
        <div className="flex items-center gap-3 rounded-lg border border-gray-300 px-3 py-2">
          <span className="flex h-8 w-8 items-center justify-center rounded-md bg-[#0F9D58]">
            <span className="hero-table-cells-solid h-5 w-5 text-white" />
          </span>
          <span className="font-medium text-gray-900">Googlesheets</span>
          <span className="text-sm text-gray-500">latest</span>
          <span className="grow" />
          <button
            type="button"
            className="rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-primary-500"
          >
            Connect
          </button>
        </div>
      </div>
    </div>
  );
}

function JobInspectorPanel() {
  const noop = () => {
    /* presentational */
  };
  return (
    <InspectorLayout title="adfasdfas" nodeType="job" onClose={noop}>
      <JobFormBody />
      <div className="px-6 py-4">
        <InspectorFooter
          leftButtons={
            <>
              <Button variant="secondary" aria-label="Open code editor">
                <span className="hero-arrows-pointing-out size-5" />
              </Button>
              <Button variant="secondary" aria-label="Delete job">
                <span className="hero-trash size-5" />
              </Button>
            </>
          }
          rightButtons={
            <Button variant="secondary">
              <span className="flex items-center gap-2">
                <span className="hero-play-solid size-4" />
                Run From Here
              </span>
            </Button>
          }
        />
      </div>
    </InspectorLayout>
  );
}

function EditorHeader() {
  return (
    <div className="flex flex-none items-center justify-between border-b border-gray-200 bg-white px-4 py-2">
      <div className="flex items-center gap-2 text-sm">
        <span className="font-medium text-gray-500">openhie-demo</span>
        <span className="hero-chevron-right h-4 w-4 text-gray-300" />
        <span className="font-semibold text-gray-900">Patient sync</span>
      </div>
      <div className="flex items-center gap-3">
        <div className="flex -space-x-2">
          <span className="flex h-7 w-7 items-center justify-center rounded-full bg-primary-500 text-xs font-semibold text-white ring-2 ring-white">
            AO
          </span>
          <span className="flex h-7 w-7 items-center justify-center rounded-full bg-emerald-500 text-xs font-semibold text-white ring-2 ring-white">
            WC
          </span>
        </div>
        <button
          type="button"
          className="rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-primary-500"
        >
          Save
        </button>
      </div>
    </div>
  );
}

const meta = {
  title: 'Editor/Canvas',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Canvas: Story = {
  render: () => (
    <div className="flex h-[720px] w-full flex-col bg-white">
      <EditorHeader />
      <div className="relative flex-1 overflow-hidden">
        <ReactFlowProvider>
          <ReactFlow
            nodes={nodes}
            edges={edges}
            nodeTypes={nodeTypes}
            edgeTypes={edgeTypes}
            fitView
            fitViewOptions={{ padding: 0.3 }}
            minZoom={0.2}
            maxZoom={1.5}
            nodesDraggable={false}
            nodesConnectable={false}
            proOptions={{ hideAttribution: true }}
          >
            <Background />
            <Controls showInteractive={false} />
            <MiniMap nodeComponent={MiniMapNode} pannable zoomable />
          </ReactFlow>
        </ReactFlowProvider>
        <div className="absolute top-0 right-0 h-full">
          <JobInspectorPanel />
        </div>
      </div>
    </div>
  ),
};
