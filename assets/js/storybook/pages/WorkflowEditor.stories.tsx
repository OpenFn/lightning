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

import MiniMapNode from '#/workflow-diagram/components/MiniMapNode';
import realEdgeTypes from '#/workflow-diagram/edges';
import realNodeTypes from '#/workflow-diagram/nodes';

import {
  AppSidebar,
  TopBar,
  Breadcrumbs,
  Crumb,
  ProjectCrumb,
  PageFrame,
} from '../liveview/_shell';

/**
 * Composite view: the workflow editor canvas — the @xyflow/react DAG from
 * `workflow-diagram/WorkflowDiagram.tsx`. Mounts a real (static) `<ReactFlow>`
 * using the diagram's own `nodeTypes`, `edgeTypes`, `<Background>`,
 * `<Controls>` and `<MiniMap>`, wrapped in the app shell with a right-hand job
 * inspector panel. Node/edge data is mocked; the canvas is not editable.
 *
 * The diagram's node/edge components are typed loosely against React Flow's
 * strict prop types (the production diagram registers them the same way), so
 * the maps are widened through `unknown` at this single boundary.
 */
const nodeTypes = realNodeTypes as unknown as NodeTypes;
const edgeTypes = realEdgeTypes as unknown as EdgeTypes;

const NODES: FlowNode[] = [
  {
    id: 'trigger-1',
    type: 'trigger',
    position: { x: 250, y: 0 },
    data: {
      id: 'trigger-1',
      name: 'webhook',
      workflow_id: 'wf-1',
      enabled: true,
      type: 'webhook',
      has_auth_method: true,
      trigger: { type: 'webhook', enabled: true, has_auth_method: true },
    },
  },
  {
    id: 'job-1',
    type: 'job',
    position: { x: 250, y: 150 },
    selected: true,
    data: {
      name: 'Transform data',
      adaptor: '@openfn/language-http@latest',
      allowPlaceholder: false,
    },
  },
  {
    id: 'job-2',
    type: 'job',
    position: { x: 60, y: 320 },
    data: {
      name: 'Upsert patients',
      adaptor: '@openfn/language-dhis2@latest',
      allowPlaceholder: false,
    },
  },
  {
    id: 'job-3',
    type: 'job',
    position: { x: 440, y: 320 },
    data: {
      name: 'Notify on failure',
      adaptor: '@openfn/language-slack@latest',
      allowPlaceholder: false,
    },
  },
];

const EDGES: FlowEdge[] = [
  { id: 'e-t-1', source: 'trigger-1', target: 'job-1', type: 'step' },
  { id: 'e-1-2', source: 'job-1', target: 'job-2', type: 'step' },
  { id: 'e-1-3', source: 'job-1', target: 'job-3', type: 'step' },
];

function InspectorPanel() {
  return (
    <aside className="flex w-96 shrink-0 flex-col border-l border-gray-200 bg-white">
      <div className="flex items-center justify-between border-b border-gray-200 px-4 py-3">
        <div className="flex items-center gap-2">
          <span className="hero-square-3-stack-3d h-5 w-5 text-gray-500" />
          <h2 className="text-sm font-semibold text-gray-900">
            Transform data
          </h2>
        </div>
        <button
          type="button"
          aria-label="Close inspector"
          className="rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-gray-500"
        >
          <span className="hero-x-mark h-5 w-5" />
        </button>
      </div>
      <div className="flex flex-col gap-4 overflow-y-auto p-4">
        <div>
          <label
            htmlFor="job-name"
            className="text-sm/6 font-medium text-slate-800"
          >
            Name
          </label>
          <input
            id="job-name"
            type="text"
            defaultValue="Transform data"
            className="mt-2 block w-full rounded-lg border-slate-300 text-slate-900 focus:border-slate-400 focus:ring-0 focus:outline-primary-600 sm:text-sm"
          />
        </div>
        <div>
          <span className="text-sm/6 font-medium text-slate-800">Adaptor</span>
          <div className="mt-2 flex items-center gap-2 rounded-lg border border-slate-300 px-3 py-2">
            <span className="flex h-6 w-6 items-center justify-center rounded bg-primary-100 text-xs font-semibold text-primary-700">
              ht
            </span>
            <span className="font-mono text-xs text-gray-700">
              @openfn/language-http
            </span>
            <span className="ml-auto rounded bg-gray-100 px-1.5 py-0.5 font-mono text-xs text-gray-500">
              latest
            </span>
          </div>
        </div>
        <button
          type="button"
          className="flex w-full items-center justify-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-gray-300 ring-inset hover:bg-gray-50"
        >
          <span className="hero-code-bracket h-4 w-4 text-gray-500" />
          Open editor
        </button>
        <p className="text-xs text-gray-500">
          Double-click a step on the canvas to open the full-screen IDE.
        </p>
      </div>
    </aside>
  );
}

const meta = {
  title: 'Pages/Workflow Editor',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Canvas: Story = {
  render: () => (
    <PageFrame sidebar={<AppSidebar variant="project" activeItem="overview" />}>
      <TopBar
        actions={
          <div className="flex items-center gap-2">
            <button
              type="button"
              className="cursor-pointer rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-gray-300 ring-inset hover:bg-gray-50"
            >
              Run
            </button>
            <button
              type="button"
              className="cursor-pointer rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-primary-500"
            >
              Save
            </button>
          </div>
        }
      >
        <Breadcrumbs>
          <ProjectCrumb label="openhie-demo" />
          <Crumb>Patient sync</Crumb>
        </Breadcrumbs>
      </TopBar>
      <div className="flex min-h-0 flex-1">
        <div className="relative flex-1 bg-gray-50">
          <ReactFlowProvider>
            <ReactFlow
              nodes={NODES}
              edges={EDGES}
              nodeTypes={nodeTypes}
              edgeTypes={edgeTypes}
              fitView
              fitViewOptions={{ padding: 0.2 }}
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
        </div>
        <InspectorPanel />
      </div>
    </PageFrame>
  ),
};
