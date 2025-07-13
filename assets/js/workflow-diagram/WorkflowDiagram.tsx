import React, { useCallback, useEffect, useRef, useState } from 'react';
import ReactFlow, {
  Controls,
  ReactFlowProvider,
  applyNodeChanges,
  getRectOfNodes,
  type NodeChange,
  type ReactFlowInstance,
  type Rect,
} from 'reactflow';

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

import { useWorkflowStore } from '../workflow-store/store';
import type { Flow, Positions } from './types';
import { getVisibleRect, isPointInRect } from './util/viewport';

type WorkflowDiagramProps = {
  el?: HTMLElement | null;
  containerEl?: HTMLElement | null;
  selection: string | null;
  onSelectionChange: (id: string | null) => void;
  forceFit?: boolean;
  showAiAssistant?: boolean;
  aiAssistantId?: string;
};

type ChartCache = {
  positions: Positions;
  lastSelection: string | null;
  lastLayout?: string;
  layoutDuration?: number;
};

const LAYOUT_DURATION = 300;

export default function WorkflowDiagram(props: WorkflowDiagramProps) {
  const { jobs, triggers, edges, disabled } = useWorkflowStore();
  const { selection, onSelectionChange, containerEl: el } = props;

  const [model, setModel] = useState<Flow.Model>({ nodes: [], edges: [] });
  const [drawerWidth, setDrawerWidth] = useState(0);
  const workflowDiagramRef = useRef<HTMLDivElement>(null);

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
    lastLayout: undefined,
  });

  const [flow, setFlow] = useState<ReactFlowInstance>();

  // Respond to changes pushed into the component from outside
  // This usually means the workflow has changed or its the first load, so we don't want to animate
  // Later, if responding to changes from other users live, we may want to animate
  useEffect(() => {
    const { positions } = chartCache.current;
    const newModel = fromWorkflow(
      workflow,
      positions,
      placeholders,
      // Re-render the model based on whatever was last selected
      // This handles first load and new node safely
      chartCache.current.lastSelection
    );
    if (flow && newModel.nodes.length) {
      const layoutId = shouldLayout(
        newModel.edges,
        chartCache.current.lastLayout
      );

      if (layoutId) {
        chartCache.current.lastLayout = layoutId;
        const viewBounds = {
          width: workflowDiagramRef.current?.clientWidth ?? 0,
          height: workflowDiagramRef.current?.clientHeight ?? 0,
        };
        layout(newModel, setModel, flow, viewBounds, {
          duration: props.layoutDuration ?? LAYOUT_DURATION,
          forceFit: props.forceFit,
        }).then(positions => {
          // Note we don't update positions until the animation has finished
          chartCache.current.positions = positions;
        });
      } else {
        // If layout is id, ensure nodes have positions
        // This is really only needed when there's a single trigger node
        newModel.nodes.forEach(n => {
          if (!n.position) {
            n.position = { x: 0, y: 0 };
          }
        });
        setModel(newModel);
      }
    } else {
      chartCache.current.positions = {};
    }
  }, [workflow, flow, placeholders, el]);

  useEffect(() => {
    const updatedModel = updateSelectionStyles(model, selection);
    setModel(updatedModel);
  }, [selection]);

  useEffect(() => {
    if (!props.showAiAssistant) {
      setDrawerWidth(0);
      return;
    }

    if (!props.aiAssistantId) {
      return;
    }

    const aiAssistantId = props.aiAssistantId;

    let observer: ResizeObserver | null = null;

    const timer = setTimeout(() => {
      const drawer = document.getElementById(aiAssistantId);
      if (drawer) {
        observer = new ResizeObserver(entries => {
          const entry = entries[0];
          if (entry) {
            const width = entry.contentRect.width;
            setDrawerWidth(width);
          }
        });
        observer.observe(drawer);
        setDrawerWidth(drawer.getBoundingClientRect().width);
      }
    }, 50);

    return () => {
      clearTimeout(timer);
      if (observer) {
        observer.disconnect();
      }
    };
  }, [props.showAiAssistant, props.aiAssistantId]);

  const onNodesChange = useCallback(
    (changes: NodeChange[]) => {
      const newNodes = applyNodeChanges(changes, model.nodes);
      setModel({ nodes: newNodes, edges: model.edges });
    },
    [setModel, model]
  );

  const handleNodeClick = useCallback(
    (event: React.MouseEvent, node: Flow.Node) => {
      if ((event.target as HTMLElement).closest('[name=add-node]')) {
        addPlaceholder(node);
      } else {
        if (node.type != 'placeholder') cancelPlaceholder();

        updateSelection(node.id);
      }
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
          cachedTargetBounds = getRectOfNodes(visible);
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

  const connectHandlers = useConnect(model, setModel);
  return (
    <ReactFlowProvider>
      <ReactFlow
        ref={workflowDiagramRef}
        maxZoom={1}
        proOptions={{ account: 'paid-pro', hideAttribution: true }}
        nodes={model.nodes}
        edges={model.edges}
        onNodesChange={onNodesChange}
        nodesDraggable={false}
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
        <Controls
          showInteractive={false}
          position="bottom-left"
          style={{
            transform: `translateX(${drawerWidth}px)`,
            transition: 'transform 500ms ease-in-out',
          }}
        />
      </ReactFlow>
    </ReactFlowProvider>
  );
}
