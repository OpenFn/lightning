/**
 * Read-only diagram preview of a template, rendered straight from its YAML.
 *
 * This deliberately does NOT go through WorkflowStore, the Y.Doc, or the
 * Phoenix channel. It reuses only the pure parts of the diagram stack —
 * `fromWorkflow`, the Dagre `layout`, and the node/edge components — so a
 * template can be looked at without a workflow existing anywhere. Browsing
 * templates therefore has no side effects: nothing is created until the user
 * explicitly asks for it.
 *
 * The preview draws shape only — node names, adaptors and how they connect.
 * Job bodies are parsed and discarded.
 */

import {
  Background,
  type EdgeTypes,
  type NodeTypes,
  ReactFlow,
  ReactFlowProvider,
  useReactFlow,
} from '@xyflow/react';
import { useEffect, useMemo, useRef, useState } from 'react';

import { FIT_PADDING } from '#/workflow-diagram/constants';
import edgeTypes from '#/workflow-diagram/edges';
import layout from '#/workflow-diagram/layout';
import nodeTypes from '#/workflow-diagram/nodes';
import type { Flow, Lightning } from '#/workflow-diagram/types';
import fromWorkflow from '#/workflow-diagram/util/from-workflow';

import type { Template } from '../types/template';
import { createEmptyRunInfo } from '../utils/runStepsTransformer';
import { templateToWorkflowState } from '../utils/templateWorkflowState';

import { ErrorBoundary } from './common/ErrorBoundary';

const EMPTY_MODEL: Flow.Model = { nodes: [], edges: [] };

export interface TemplatePreviewProps {
  template: Template;
}

export function TemplatePreview({ template }: TemplatePreviewProps) {
  // The boundary is the outermost layer on purpose: the preview is a nicety,
  // and it must never be able to take the template browser — or the workflow
  // creation path behind it — down with it. Callers key this component by
  // template id, so switching template also resets a tripped boundary.
  //
  // Each preview gets its own ReactFlowProvider so it cannot share viewport or
  // node state with the real canvas.
  return (
    <ErrorBoundary
      label="Template preview"
      // No retry: re-rendering the same template would fail the same way, and
      // the user's way out is simply to pick another one.
      fallback={() => (
        <PreviewFallback message="This template can't be previewed." />
      )}
    >
      <ReactFlowProvider>
        <TemplatePreviewFlow template={template} />
      </ReactFlowProvider>
    </ErrorBoundary>
  );
}

function PreviewFallback({
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

function TemplatePreviewFlow({ template }: TemplatePreviewProps) {
  const flow = useReactFlow();
  const containerRef = useRef<HTMLDivElement>(null);
  const [model, setModel] = useState<Flow.Model>(EMPTY_MODEL);

  // A user-published template can contain YAML we can't parse. That must not
  // take the modal down with it.
  const parsed = useMemo(() => {
    try {
      return {
        state: templateToWorkflowState(template),
        error: null as string | null,
      };
    } catch (error) {
      return {
        state: null,
        error:
          error instanceof Error
            ? error.message
            : "This template's definition could not be read.",
      };
    }
  }, [template]);

  useEffect(() => {
    if (!parsed.state) {
      setModel(EMPTY_MODEL);
      return;
    }

    const { jobs, triggers, edges } = parsed.state;

    // `disabled: true` suppresses the placeholder "+" affordances on nodes.
    // Positions are passed empty so Dagre always lays the preview out fresh: a
    // template's own `pos` values were authored against a full-size canvas, and
    // reusing them here would push nodes out of this much smaller pane. The
    // preview therefore shows the shape of the workflow, not the exact layout
    // the user will land on after creating it.
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
      {},
      EMPTY_MODEL,
      createEmptyRunInfo(),
      null
    );

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
      // user switches template — ReactFlow instead holds the fit until the
      // nodes are measured, then runs it once.
      { duration: false }
    );
  }, [parsed, flow]);

  if (parsed.error) {
    return (
      <PreviewFallback
        message="This template can't be previewed."
        detail={parsed.error}
      />
    );
  }

  return (
    <div ref={containerRef} className="h-full w-full">
      <ReactFlow
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
