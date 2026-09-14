/**
 * Read-only diagram of a workflow state, drawn without the editor.
 *
 * This deliberately does NOT go through WorkflowStore, the Y.Doc, or the
 * Phoenix channel. It reuses only the pure parts of the diagram stack —
 * `fromWorkflow`, the Dagre `layout`, and the node/edge components — so a
 * workflow can be looked at before one exists anywhere. Showing a preview
 * therefore has no side effects: nothing is created until the user explicitly
 * asks for it.
 *
 * It takes a parsed `WorkflowState` rather than anything template-shaped, so
 * whoever renders it owns the parse and can report a failure in its own words.
 *
 * The preview draws shape only — node names, adaptors and how they connect.
 * Job bodies are carried in the state and never displayed.
 */

import {
  Background,
  type EdgeTypes,
  type NodeTypes,
  ReactFlow,
  ReactFlowProvider,
  useReactFlow,
} from '@xyflow/react';
import { memo, useEffect, useRef, useState } from 'react';

import { FIT_PADDING } from '#/workflow-diagram/constants';
import edgeTypes from '#/workflow-diagram/edges';
import layout from '#/workflow-diagram/layout';
import nodeTypes from '#/workflow-diagram/nodes';
import type { Flow, Lightning } from '#/workflow-diagram/types';
import fromWorkflow from '#/workflow-diagram/util/from-workflow';

import type { WorkflowState } from '../../yaml/types';
import { createEmptyRunInfo } from '../utils/runStepsTransformer';

import { ErrorBoundary } from './common/ErrorBoundary';

const EMPTY_MODEL: Flow.Model = { nodes: [], edges: [] };

export interface WorkflowPreviewProps {
  state: WorkflowState;
}

// Memoised because hosts re-render for reasons that have nothing to do with the
// diagram — scrolling a list beside it, say — and re-running a ReactFlow tree
// is not cheap. `state` is the only prop, so a host that keeps it stable, as
// one parsing under useMemo does, redraws only when the workflow itself
// changes.
export const WorkflowPreview = memo(function WorkflowPreview({
  state,
}: WorkflowPreviewProps) {
  // The boundary is the outermost layer on purpose: the preview is a nicety,
  // and it must never be able to take its host — or the workflow creation path
  // behind it — down with it. Callers key this component by whatever they are
  // previewing, so switching also resets a tripped boundary.
  //
  // Each preview gets its own ReactFlowProvider so it cannot share viewport or
  // node state with the real canvas.
  return (
    <ErrorBoundary
      label="WorkflowPreview"
      // No retry: re-rendering the same state would fail the same way, and the
      // user's way out is simply to pick something else.
      fallback={() => <PreviewMessage message="This can't be previewed." />}
    >
      <ReactFlowProvider>
        <WorkflowPreviewFlow state={state} />
      </ReactFlowProvider>
    </ErrorBoundary>
  );
});

/**
 * The preview pane's text state — "nothing selected", "can't be read", and the
 * boundary's fallback all look the same, so they share one component rather
 * than three copies of the same centred paragraph.
 */
export function PreviewMessage({
  message,
  detail,
}: {
  message: string;
  detail?: string;
}) {
  return (
    <div className="flex h-full w-full items-center justify-center p-6">
      <p className="text-center text-sm text-gray-500">
        {message}
        {detail && (
          <>
            <br />
            <span className="text-xs text-gray-400">{detail}</span>
          </>
        )}
      </p>
    </div>
  );
}

function WorkflowPreviewFlow({ state }: WorkflowPreviewProps) {
  const flow = useReactFlow();
  const containerRef = useRef<HTMLDivElement>(null);
  const [model, setModel] = useState<Flow.Model>(EMPTY_MODEL);

  useEffect(() => {
    const { jobs, triggers, edges, positions } = state;

    // Authored positions are the ones that get applied when this state is
    // turned into a real workflow, so draw those rather than laying out fresh.
    // Otherwise the preview shows a tidy Dagre graph and the created workflow
    // opens in whatever arrangement its author left behind.
    //
    // A partial set is treated as none: every node needs a position, and
    // falling back to a full layout beats inventing the missing ones.
    const placed =
      positions && [...jobs, ...triggers].every(node => positions[node.id])
        ? positions
        : null;

    // `disabled: true` suppresses the placeholder "+" affordances on nodes.
    // The cast is pre-existing type debt shared with WorkflowDiagram.tsx: the
    // YAML state types and the diagram's Lightning.* types describe the same
    // data but are declared separately.
    const initial = fromWorkflow(
      {
        jobs,
        triggers,
        edges,
        disabled: true,
      } as unknown as Lightning.Workflow,
      placed ?? {},
      EMPTY_MODEL,
      createEmptyRunInfo(),
      null
    );

    if (placed) {
      // `layout` runs Dagre unconditionally, so authored positions only survive
      // if it is skipped entirely. Framing is still ReactFlow's job: `fitView`
      // below fits whatever bounds these positions produce, down to the
      // `minZoom` floor — an arrangement spread wider than that shows its
      // middle only, and panning and zooming are off.
      setModel(initial);
      return;
    }

    const rect = containerRef.current?.getBoundingClientRect();
    void layout(
      initial,
      setModel,
      flow,
      { width: rect?.width ?? 0, height: rect?.height ?? 0 },
      // `duration: false` skips interpolating the nodes into place — there is
      // no previous layout to animate from.
      //
      // Deliberately no `forceFit`: framing the graph is left to ReactFlow's
      // own `fitView` prop below. `forceFit` would fit on a fixed 20ms timer,
      // which both races node measurement and outlives this component when the
      // caller switches to another workflow — ReactFlow instead holds the fit
      // until the nodes are measured, then runs it once.
      { duration: false }
    );
  }, [state, flow]);

  return (
    <div ref={containerRef} className="h-full w-full">
      <ReactFlow
        // Without this the diagram is an unlabelled graphics region. The name
        // comes from the state rather than the caller so every host gets one;
        // it can be blank, since the blank-workflow YAML ships without a name.
        aria-label={
          state.name ? `Preview of ${state.name}` : 'Workflow preview'
        }
        nodes={model.nodes}
        edges={model.edges}
        nodeTypes={nodeTypes as unknown as NodeTypes}
        edgeTypes={edgeTypes as unknown as EdgeTypes}
        proOptions={{ account: 'paid-pro', hideAttribution: true }}
        // Read-only is a prop combination in ReactFlow, not a single flag.
        nodesDraggable={false}
        nodesConnectable={false}
        nodesFocusable={false}
        edgesFocusable={false}
        elementsSelectable={false}
        panOnDrag={false}
        panOnScroll={false}
        zoomOnScroll={false}
        zoomOnPinch={false}
        zoomOnDoubleClick={false}
        // Defaults to true, which traps page/modal scroll under the pointer.
        preventScrolling={false}
        deleteKeyCode={null}
        fitView
        fitViewOptions={{ padding: FIT_PADDING }}
        maxZoom={1}
        minZoom={0.2}
      >
        {/* Propless, matching the real canvas, so the preview reads as the
            same surface rather than a differently-styled one. */}
        <Background />
      </ReactFlow>
    </div>
  );
}
