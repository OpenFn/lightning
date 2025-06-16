import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ReactFlow,
  Controls,
  ControlButton,
  ReactFlowProvider,
  applyNodeChanges,
  getNodesBounds,
  MiniMap,
  Background,
  type NodeChange,
  type ReactFlowInstance,
  type Rect,
} from '@xyflow/react';
import tippy, { type Instance as TippyInstance } from 'tippy.js';

import { FIT_DURATION, FIT_PADDING } from './constants';
import MiniMapNode from './components/MiniMapNode';
import edgeTypes from './edges';
import layout from './layout';
import nodeTypes from './nodes';
import useConnect from './useConnect';
import usePlaceholders from './usePlaceholders';
import fromWorkflow from './util/from-workflow';
import shouldLayout from './util/should-layout';
import throttle from './util/throttle';

import { useWorkflowStore } from '../workflow-store/store';
import type { Flow, Positions } from './types';
import { getVisibleRect, isPointInRect } from './util/viewport';

type WorkflowDiagramProps = {
  el?: HTMLElement | null;
  containerEl?: HTMLElement | null;
  selection: string | null;
  onSelectionChange: (id: string | null) => void;
  forceFit?: boolean;
};

export type ChartCache = {
  positions: Positions;
  lastSelection: string | null;
  lastLayout?: string;
  layoutDuration?: number;
};

const LAYOUT_DURATION = 300;

// Simple React hook for Tippy tooltips that finds buttons by their content
const useTippyForControls = fixedPositions => {
  useEffect(() => {
    // Find the control buttons and initialize tooltips based on their dataset attributes
    const buttons = document.querySelectorAll('.react-flow__controls button');

    buttons.forEach(button => {
      if (button instanceof HTMLElement && button.dataset.tooltip) {
        tippy(button, {
          content: button.dataset.tooltip,
          placement: 'right',
          animation: false,
          allowHTML: false,
        });
      }
    });

    return () => {
      // Destroy all tooltips when the component unmounts
      buttons.forEach(button => {
        const instance = tippy(button);
        if (instance) {
          instance.destroy();
        }
      });
    };
  }, [fixedPositions]); // Only run once on mount
};

export default function WorkflowDiagram(props: WorkflowDiagramProps) {
  const { selection, onSelectionChange, containerEl: el } = props;

  const {
    jobs,
    triggers,
    edges,
    disabled,
    positions: fixedPositions,
    options = { autolayout: true },
    updatePositions,
  } = useWorkflowStore();

  const [model, setModel] = useState<Flow.Model>({ nodes: [], edges: [] });

  const workflowDiagramRef = useRef<HTMLDivElement>(null);

  const toggleAutoLayout = useCallback(() => {
    if (fixedPositions) {
      // set positions to null to enable auto layout
      updatePositions(null);
      forceLayout();
    } else {
      // fix positions to enable manual layout
      updatePositions(chartCache.current.positions);
    }
  }, [fixedPositions]);

  const updateSelection = useCallback(
    (id?: string | null) => {
      id = id || null;

      chartCache.current.lastSelection = id;
      onSelectionChange(id);
    },
    [onSelectionChange, selection]
  );

  const {
    placeholders,
    add: addPlaceholder,
    cancel: cancelPlaceholder,
  } = usePlaceholders(el, updateSelection);

  const workflow = React.useMemo(
    () => ({
      jobs,
      triggers,
      edges,
      disabled,
    }),
    [jobs, triggers, edges, disabled]
  );

  // Track positions and selection on a ref, as a passive cache, to prevent re-renders

  const chartCache = useRef<ChartCache>({
    positions: {},
    // This will set the initial selection into the cache
    lastSelection: selection,
  });

  const [flow, setFlow] = useState<ReactFlowInstance>();

  const forceLayout = useCallback(
    (newModel?: Flow.Model) => {
      const viewBounds = {
        width: workflowDiagramRef.current?.clientWidth ?? 0,
        height: workflowDiagramRef.current?.clientHeight ?? 0,
      };
      layout(newModel ?? model, setModel, flow, viewBounds, {
        duration: props.layoutDuration ?? LAYOUT_DURATION,
        forceFit: props.forceFit,
      }).then(positions => {
        // Note we don't update positions until the animation has finished
        chartCache.current.positions = positions;
      });
    },
    [flow, model]
  );

  // Respond to changes pushed into the component from outside
  // This usually means the workflow has changed or its the first load, so we don't want to animate
  // Later, if responding to changes from other users live, we may want to animate
  useEffect(() => {
    // const newModel = fromWorkflow(
    //   workflow,
    //   fixedPositions,
    //   placeholders,
    //   // Re-render the model based on whatever was last selected
    //   // This handles first load and new node safely
    //   chartCache.current.lastSelection
    // );

    // setModel(newModel);

    const { positions: prevPositions } = chartCache.current;
    const newModel = fromWorkflow(
      // { jobs, triggers, edges },
      workflow,
      fixedPositions || prevPositions,
      placeholders,
      // Re-render the model based on whatever was last selected
      // This handles first load and new node safely
      chartCache.current.lastSelection
    );

    const layoutId = shouldLayout(
      newModel.edges,
      chartCache.current.lastLayout
    );

    if (options.autolayout) {
      forceLayout(newModel);
    } else {
      // do nothing I guess
    }
    // when do I setModel?
    // need to use shallow diffing or call selectively
    if (layoutId) {
      setModel(newModel);
    }

    // // Look at the new model structure through the edges
    // // This will tell us if there's been a structural change
    // // in the model and force an update
    // const layoutId = shouldLayout(
    //   newModel.edges,
    //   chartCache.current.lastLayout
    // );
    // if (fixedPositions) {
    //   if (layoutId) {
    //     updatePositions(fixedPositions);

    //     chartCache.current.lastLayout = layoutId;
    //     chartCache.current.positions = fixedPositions;
    //   }
    //   setModel(newModel);
    // } else if (flow && newModel.nodes.length) {
    //   if (layoutId || fixedPositions === null) {
    //     chartCache.current.lastLayout = layoutId;
    //     forceLayout(newModel);
    //   } else {
    //     // If layout is id, ensure nodes have positions
    //     // This is really only needed when there's a single trigger node
    //     newModel.nodes.forEach(n => {
    //       if (!n.position) {
    //         n.position = { x: 0, y: 0 };
    //       }
    //     });
    //     setModel(newModel);
    //   }
    // } else {
    //   // reset chart cache
    //   chartCache.current.positions = {};
    // }
  }, [workflow, flow, placeholders, el, updatePositions]);

  const onNodesChange = useCallback(
    (changes: NodeChange[]) => {
      const newNodes = applyNodeChanges(changes, model.nodes);
      setModel({ nodes: newNodes, edges: model.edges });

      if (fixedPositions) {
        const newPositions = newNodes.reduce((obj, next) => {
          obj[next.id] = next.position;
          return obj;
        }, {} as Positions);
        chartCache.current.positions = newPositions;
        updatePositions(newPositions);
      }
    },
    [setModel, model, fixedPositions, updatePositions]
  );

  const handleNodeClick = useCallback(
    (_event: React.MouseEvent, node: Flow.Node) => {
      if (node.type != 'placeholder') cancelPlaceholder();
      updateSelection(node.id);
    },
    [updateSelection]
  );

  const handleEdgeClick = useCallback(
    (_event: React.MouseEvent, edge: Flow.Edge) => {
      cancelPlaceholder();
      updateSelection(edge.id);
    },
    [updateSelection]
  );

  const handleBackgroundClick = useCallback(
    (event: React.MouseEvent) => {
      if (
        event.target instanceof HTMLElement &&
        event.target.classList?.contains('react-flow__pane')
      ) {
        cancelPlaceholder();
        updateSelection(null);
      }
    },
    [updateSelection]
  );

  // Trigger a fit to bounds when the parent div changes size
  // To keep the chart more stable, try and take a snapshot of the target bounds
  // when a new resize starts
  // This will be imperfect but stops the user completely losing context
  useEffect(() => {
    if (flow && el) {
      let isFirstCallback = true;

      let cachedTargetBounds: Rect | null = null;
      let cacheTimeout: any;

      const throttledResize = throttle(() => {
        clearTimeout(cacheTimeout);

        // After 3 seconds, clear the timeout and take a new cache snapshot
        cacheTimeout = setTimeout(() => {
          cachedTargetBounds = null;
        }, 3000);

        if (!cachedTargetBounds) {
          // Take a snapshot of what bounds to try and maintain throughout the resize
          const viewBounds = {
            width: el.clientWidth ?? 0,
            height: el.clientHeight ?? 0,
          };
          const rect = getVisibleRect(flow.getViewport(), viewBounds, 1);
          const visible = model.nodes.filter(n =>
            isPointInRect(n.position, rect)
          );
          cachedTargetBounds = getNodesBounds(visible);
        }

        // Run an animated fit
        flow.fitBounds(cachedTargetBounds, {
          duration: FIT_DURATION,
          padding: FIT_PADDING,
        });
      }, FIT_DURATION * 2);

      const resizeOb = new ResizeObserver(function (entries) {
        if (!isFirstCallback) {
          // Don't fit when the listener attaches (it callsback immediately)
          throttledResize();
        }
        isFirstCallback = false;
      });
      resizeOb.observe(el);

      return () => {
        throttledResize.cancel();
        resizeOb.unobserve(el);
      };
    }
  }, [flow, model, el]);

  const connectHandlers = useConnect(model, setModel, addPlaceholder, flow);

  // Set up tooltips for control buttons
  useTippyForControls(fixedPositions);

  return (
    <ReactFlowProvider>
      <ReactFlow
        ref={workflowDiagramRef}
        maxZoom={1}
        proOptions={{ account: 'paid-pro', hideAttribution: true }}
        nodes={model.nodes}
        edges={model.edges}
        onNodesChange={onNodesChange}
        nodesDraggable={fixedPositions}
        nodeTypes={nodeTypes}
        edgeTypes={edgeTypes}
        onClick={handleBackgroundClick}
        onNodeClick={handleNodeClick}
        onEdgeClick={handleEdgeClick}
        onInit={setFlow}
        deleteKeyCode={null}
        fitView
        fitViewOptions={{ padding: FIT_PADDING }}
        minZoom={0.2}
        {...connectHandlers}
      >
        <Controls position="bottom-left" showInteractive={false}>
          <ControlButton
            onClick={toggleAutoLayout}
            data-tooltip={
              fixedPositions
                ? 'Switch to auto layout'
                : 'Switch to manual layout'
            }
          >
            {fixedPositions ? (
              <span className="text-black hero-sparkles w-4 h-4" />
            ) : (
              <span className="text-primary-600 hero-sparkles-solid w-4 h-4" />
            )}
          </ControlButton>
          <ControlButton
            onClick={() => forceLayout()}
            data-tooltip="Force auto-layout (override all manual positions)"
          >
            <span className="text-black hero-squares-2x2 w-4 h-4" />
          </ControlButton>
        </Controls>
        <Background />
        <MiniMap
          zoomable
          pannable
          className="border border-2 border-gray-200"
          nodeComponent={MiniMapNode}
        />
      </ReactFlow>
    </ReactFlowProvider>
  );
}
