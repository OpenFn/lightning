import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ReactFlow,
  Controls,
  ReactFlowProvider,
  applyNodeChanges,
  getNodesBounds,
  type NodeChange,
  type ReactFlowInstance,
  type Rect,
  ControlButton,
  Background,
  MiniMap,
} from '@xyflow/react';

import { FIT_DURATION, FIT_PADDING } from './constants';
import edgeTypes from './edges';
import layout from './layout';
import nodeTypes from './nodes';
import useConnect from './useConnect';
import usePlaceholders from './usePlaceholders';
import fromWorkflow from './util/from-workflow';
import shouldLayout from './util/should-layout';
import throttle from './util/throttle';
import updateSelectionStyles from './util/update-selection';
import tippy from 'tippy.js';
import { useWorkflowStore } from '../workflow-store/store';
import type { Flow, Positions } from './types';
import { getVisibleRect, isPointInRect } from './util/viewport';
import MiniMapNode from './components/MiniMapNode';

type WorkflowDiagramProps = {
  el?: HTMLElement | null;
  containerEl?: HTMLElement | null;
  selection: string | null;
  onSelectionChange: (id: string | null) => void;
  forceFit?: boolean;
};

type ChartCache = {
  positions: Positions;
  lastSelection: string | null;
  lastLayout?: string;
  layoutDuration?: number;
};

const LAYOUT_DURATION = 300;

// Simple React hook for Tippy tooltips that finds buttons by their content
const useTippyForControls = (isManualLayout: boolean) => {
  useEffect(() => {
    // Find the control buttons and initialize tooltips based on their dataset attributes
    const buttons = document.querySelectorAll('.react-flow__controls button');

    const cleaner: (() => void)[] = [];
    buttons.forEach(button => {
      if (button instanceof HTMLElement && button.dataset.tooltip) {
        const tp = tippy(button, {
          content: button.dataset.tooltip,
          placement: 'right',
          animation: false,
          allowHTML: false,
        });
        cleaner.push(tp.destroy.bind(tp));
      }
    });

    return () => {
      cleaner.forEach(f => {
        f();
      });
    };
  }, [isManualLayout]); // Only run once on mount
};

export default function WorkflowDiagram(props: WorkflowDiagramProps) {
  const {
    jobs,
    triggers,
    edges,
    disabled,
    positions: fixedPositions,
    updatePositions,
    updatePosition,
    undo,
    redo
  } = useWorkflowStore();
  const isManualLayout = !!fixedPositions;
  // value of select in props seems same as select in store. one in props is always set on initial render. (helps with refresh)
  const { selection, onSelectionChange, containerEl: el } = props;

  const [model, setModel] = useState<Flow.Model>({ nodes: [], edges: [] });
  const workflowDiagramRef = useRef<HTMLDivElement>(null);

  const updateSelection = useCallback(
    (id?: string | null) => {
      id = id || null;

      chartCache.current.lastSelection = id;
      onSelectionChange(id);
    },
    [onSelectionChange]
  );

  // selection can be null give 2 events
  // 1. we click empty space on editor (client event)
  // 2. selection prop becomes null (server event)
  // on option 2. chartCache isn't updated. Hence we call updateSelection to do that
  useEffect(() => {
    // we know selection from server has changed when it's not equal to the one on client
    if (selection !== chartCache.current.lastSelection) updateSelection(selection);
  }, [selection, updateSelection])

  const {
    placeholders,
    add: addPlaceholder,
    cancel: cancelPlaceholder,
    updatePlaceholderPosition,
  } = usePlaceholders(el, isManualLayout, updateSelection);

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
    lastLayout: undefined,
  });

  const [flow, setFlow] = useState<ReactFlowInstance>();

  const forceLayout = useCallback(() => {
    const viewBounds = {
      width: workflowDiagramRef.current?.clientWidth ?? 0,
      height: workflowDiagramRef.current?.clientHeight ?? 0,
    };
    return layout(model, setModel, flow, viewBounds, {
      duration: props.layoutDuration ?? LAYOUT_DURATION,
      forceFit: props.forceFit,
    }).then(positions => {
      // Note we don't update positions until the animation has finished
      chartCache.current.positions = positions;
      if (isManualLayout) updatePositions(positions);
    });
  }, [flow, model, isManualLayout, updatePositions]);

  // Respond to changes pushed into the component from outside
  // This usually means the workflow has changed or its the first load, so we don't want to animate
  // Later, if responding to changes from other users live, we may want to animate
  useEffect(() => {
    const { positions, lastSelection } = chartCache.current;
    // create model from workflow and also apply selection styling to the model.
    const newModel = updateSelectionStyles(
      fromWorkflow(
        workflow,
        positions,
        placeholders,
        // Re-render the model based on whatever was last selected
        // This handles first load and new node safely
        lastSelection
      ),
      lastSelection
    );
    if (flow && newModel.nodes.length) {
      const layoutId = shouldLayout(
        newModel.edges,
        newModel.nodes,
        isManualLayout,
        chartCache.current.lastLayout
      );

      if (layoutId) {
        chartCache.current.lastLayout = layoutId;
        const viewBounds = {
          width: workflowDiagramRef.current?.clientWidth ?? 0,
          height: workflowDiagramRef.current?.clientHeight ?? 0,
        };
        if (isManualLayout) {
          // give nodes positions
          const nodesWPos = newModel.nodes.map(node => {
            // during manualLayout. a placeholder wouldn't have position in positions in store
            // hence use the position on the placeholder node
            const isPlaceholder = node.type === 'placeholder';
            return {
              ...node,
              position: isPlaceholder ? node.position : fixedPositions[node.id],
            };
          });
          setModel({ ...newModel, nodes: nodesWPos });
          chartCache.current.positions = fixedPositions;
        } else {
          layout(newModel, setModel, flow, viewBounds, {
            duration: props.layoutDuration ?? LAYOUT_DURATION,
            forceFit: props.forceFit,
          }).then(positions => {
            // Note we don't update positions until the animation has finished
            chartCache.current.positions = positions;
          });
        }
      } else {
        // If layout is id, ensure nodes have positions
        // This is really only needed when there's a single trigger node
        newModel.nodes.forEach(n => {
          // if isManualLayout, then we use values from store instead
          if (isManualLayout && n.type !== 'placeholder')
            n.position = fixedPositions[n.id];
          if (!n.position) {
            n.position = { x: 0, y: 0 };
          }
        });
        setModel(newModel);
      }
    } else {
      chartCache.current.positions = {};
    }
  }, [workflow, flow, placeholders, el, isManualLayout, fixedPositions, selection]);

  const onNodesChange = useCallback(
    (changes: NodeChange[]) => {
      const newNodes = applyNodeChanges(changes, model.nodes);
      setModel({ nodes: newNodes, edges: model.edges });

      // we just need to recalculate this to update the cache.
      const newPositions = newNodes.reduce((obj, next) => {
        obj[next.id] = next.position;
        return obj;
      }, {} as Positions);
      chartCache.current.positions = newPositions;
    },
    [setModel, model]
  );

  // update node position data only on dragstop.
  const onNodeDragStop = useCallback(
    (e: React.MouseEvent, node: Flow.Node) => {
      if (node.type === 'placeholder') {
        updatePlaceholderPosition(node.id, node.position);
      } else {
        updatePosition(node.id, node.position);
      }
    },
    [updatePosition, updatePlaceholderPosition]
  );

  const handleNodeClick = useCallback(
    (event: React.MouseEvent, node: Flow.Node) => {
      if (
        (event.target as HTMLElement).getAttribute('data-handleid') ===
        'node-connector'
      ) {
        addPlaceholder(node);
        return;
      }
      if (node.type !== 'placeholder') cancelPlaceholder();
      updateSelection(node.id);
    },
    [updateSelection, cancelPlaceholder, addPlaceholder]
  );

  const handleEdgeClick = useCallback(
    (_event: React.MouseEvent, edge: Flow.Edge) => {
      cancelPlaceholder();
      updateSelection(edge.id);
    },
    [updateSelection, cancelPlaceholder]
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

  const switchLayout = async () => {
    if (isManualLayout) {
      updatePositions(null);
    } else updatePositions(chartCache.current.positions);
  };

  const handleFitView = useCallback(async () => {
    const bounds = getNodesBounds(model.nodes);
    flow.fitBounds(bounds, {
      duration: 200,
      padding: FIT_PADDING,
    });
  }, [model, flow]);

  const connectHandlers = useConnect(
    model,
    setModel,
    addPlaceholder,
    () => {
      cancelPlaceholder();
      updateSelection(null);
    },
    flow
  );
  // Set up tooltips for control buttons
  useTippyForControls(isManualLayout);
  return (
    <ReactFlowProvider>
      <ReactFlow
        ref={workflowDiagramRef}
        maxZoom={1}
        proOptions={{ account: 'paid-pro', hideAttribution: true }}
        nodes={model.nodes}
        edges={model.edges}
        onNodesChange={onNodesChange}
        onNodeDragStop={onNodeDragStop}
        nodesDraggable={isManualLayout}
        nodeTypes={nodeTypes}
        edgeTypes={edgeTypes}
        onNodeClick={handleNodeClick}
        onEdgeClick={handleEdgeClick}
        onInit={setFlow}
        deleteKeyCode={null}
        fitView
        fitViewOptions={{ padding: FIT_PADDING }}
        minZoom={0.2}
        {...connectHandlers}
      >
        <Controls
          position="bottom-left"
          showInteractive={false}
          showFitView={false}
        >
          <ControlButton onClick={handleFitView} data-tooltip="Fit view">
            <span className="text-black hero-viewfinder-circle w-4 h-4" />
          </ControlButton>

          <ControlButton
            onClick={switchLayout}
            data-tooltip={
              isManualLayout
                ? 'Switch to auto layout mode'
                : 'Switch to manual layout mode'
            }
          >
            {isManualLayout ? (
              <span className="text-black hero-cursor-arrow-rays w-4 h-4" />
            ) : (
              <span className="text-black hero-cursor-arrow-ripple w-4 h-4" />
            )}
          </ControlButton>
          <ControlButton
            onClick={forceLayout}
            data-tooltip="Run auto layout (override manual positions)"
          >
            <span className="text-black hero-squares-2x2 w-4 h-4" />
          </ControlButton>
          <ControlButton
            onClick={undo}
            data-tooltip="Undo"
          >
            <span className="text-black hero-arrow-uturn-left w-4 h-4" />
          </ControlButton>
          <ControlButton
            onClick={redo}
            data-tooltip="Redo"
          >
            <span className="text-black hero-arrow-uturn-right w-4 h-4" />
          </ControlButton>

        </Controls>
        <Background />
        <MiniMap
          zoomable
          pannable
          className="border-2 border-gray-200"
          nodeComponent={MiniMapNode}
        />
      </ReactFlow>
    </ReactFlowProvider>
  );
}
