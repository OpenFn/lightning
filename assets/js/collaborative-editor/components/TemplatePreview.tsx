import {
  Background,
  ReactFlow,
  ReactFlowProvider,
  type EdgeTypes,
  type NodeTypes,
} from '@xyflow/react';
import { useMemo } from 'react';

import { FIT_PADDING } from '#/workflow-diagram/constants';
import edgeTypes from '#/workflow-diagram/edges';
import nodeTypes from '#/workflow-diagram/nodes';
import type { Flow, Lightning, Positions } from '#/workflow-diagram/types';
import fromWorkflow from '#/workflow-diagram/util/from-workflow';
import computeStaticPositions from '#/workflow-diagram/util/static-layout';

import { convertWorkflowSpecToState, parseWorkflowYAML } from '../../yaml/util';
import type { Template } from '../types/template';
import { createEmptyRunInfo } from '../utils/runStepsTransformer';

/**
 * Positions for the preview, in order of preference:
 * 1. `pos:` keys embedded in the template YAML (hoisted by
 *    `convertWorkflowSpecToState`, keyed by the ids it resolves)
 * 2. the template record's saved `positions` map (only lines up when the
 *    YAML carries node ids, since keys are the original workflow's ids)
 * 3. a fresh Dagre auto-layout
 *
 * A source is only used when it covers every node — a half-positioned graph
 * looks broken, so anything partial falls through to Dagre.
 */
function resolvePositions(
  template: Template,
  statePositions: Positions | null,
  model: Flow.Model
): Positions {
  const savedPositions =
    'positions' in template ? template.positions : undefined;

  for (const candidate of [statePositions, savedPositions]) {
    if (candidate && model.nodes.every(node => candidate[node.id])) {
      return candidate;
    }
  }

  return computeStaticPositions(model);
}

/**
 * Converts a template's YAML into a react-flow model using the exact same
 * pipeline the editor uses (`parseWorkflowYAML` → `convertWorkflowSpecToState`
 * → `fromWorkflow`), so the preview stays visually identical to the diagram.
 *
 * Throws on malformed template code — callers render a fallback.
 */
function buildPreviewModel(template: Template): Flow.Model {
  const state = convertWorkflowSpecToState(parseWorkflowYAML(template.code));

  // `disabled: true` suppresses the placeholder ("+") affordances on nodes.
  // StateJob/StateTrigger lack a few fields Lightning.Workflow declares
  // (e.g. workflow_id), but nothing in the render path reads them.
  const workflow = {
    id: state.id,
    jobs: state.jobs,
    triggers: state.triggers,
    edges: state.edges,
    disabled: true,
    positions: {},
  } as unknown as Lightning.Workflow;

  // First pass without positions just to get the node/edge model...
  const model = fromWorkflow(
    workflow,
    {},
    { nodes: [], edges: [] },
    createEmptyRunInfo(),
    null
  );

  // ...then place every node from the best available source. resolvePositions
  // only returns a source that covers every node, so the fallback can't hit.
  const positions = resolvePositions(template, state.positions, model);
  model.nodes = model.nodes.map(node => ({
    ...node,
    position: positions[node.id] ?? { x: 0, y: 0 },
  }));

  return model;
}

export interface TemplatePreviewProps {
  template: Template;
}

/**
 * A static, read-only rendering of a template's workflow graph. Reuses the
 * workflow-diagram primitives (node/edge types, styles, Dagre layout) with
 * none of the collaborative editor's Y.Doc/store machinery.
 */
export function TemplatePreview({ template }: TemplatePreviewProps) {
  const model = useMemo(() => {
    try {
      return buildPreviewModel(template);
    } catch {
      return null;
    }
  }, [template]);

  if (!model) {
    return (
      <div className="flex h-full items-center justify-center">
        <p className="text-sm text-gray-400">
          Preview unavailable for this template.
        </p>
      </div>
    );
  }

  return (
    <ReactFlowProvider>
      <ReactFlow
        // Remount per template so fitView re-frames the new graph
        key={template.id}
        aria-label={`Preview of ${template.name}`}
        nodes={model.nodes}
        edges={model.edges}
        nodeTypes={nodeTypes as unknown as NodeTypes}
        edgeTypes={edgeTypes as unknown as EdgeTypes}
        proOptions={{ account: 'paid-pro', hideAttribution: true }}
        fitView
        fitViewOptions={{ padding: FIT_PADDING }}
        minZoom={0.1}
        maxZoom={1}
        nodesDraggable={false}
        nodesConnectable={false}
        nodesFocusable={false}
        edgesFocusable={false}
        elementsSelectable={false}
        zoomOnScroll={false}
        zoomOnDoubleClick={false}
        preventScrolling={false}
        deleteKeyCode={null}
      >
        <Background />
      </ReactFlow>
    </ReactFlowProvider>
  );
}
