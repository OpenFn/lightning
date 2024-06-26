import React, { useCallback, useEffect, useRef, useState } from 'react';
import ReactFlow, {
  Controls,
  ControlButton,
  NodeChange,
  ReactFlowInstance,
  ReactFlowProvider,
  applyNodeChanges,
} from 'reactflow';
import { useStore, StoreApi } from 'zustand';
import { shallow } from 'zustand/shallow';
import { ViewfinderCircleIcon, XMarkIcon } from '@heroicons/react/24/outline';

import layout from './layout';
import nodeTypes from './nodes';
import edgeTypes from './edges';
import usePlaceholders from './usePlaceholders';
import useConnect from './useConnect';
import fromWorkflow from './util/from-workflow';
import throttle from './util/throttle';
import updateSelectionStyles from './util/update-selection';
import { FIT_DURATION, FIT_PADDING } from './constants';
import shouldLayout from './util/should-layout';

import type { WorkflowState } from '../workflow-editor/store';
import type { Flow, Positions } from './types';

type WorkflowDiagramProps = {
  selection: string | null;
  onSelectionChange: (id: string | null) => void;
  store: StoreApi<WorkflowState>;
};

type ChartCache = {
  positions: Positions;
  lastSelection: string | null;
  lastLayout?: string;
};

export default React.forwardRef<HTMLElement, WorkflowDiagramProps>(
  (props, ref) => {
    const { selection, onSelectionChange, store } = props;

    const [model, setModel] = useState<Flow.Model>({ nodes: [], edges: [] });

    const [autofit, setAutofit] = useState<boolean>(true);

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
    } = usePlaceholders(ref, store, updateSelection);

    const workflow = useStore(
      store!,
      state => ({
        jobs: state.jobs,
        triggers: state.triggers,
        edges: state.edges,
      }),
      shallow
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

          // ignore autofit option for now
          // I'll remove the option later
          const autofit = false;

          layout(newModel, setModel, flow, { duration: 300, autofit }).then(
            positions => {
              // Note we don't update positions until the animation has finished
              chartCache.current.positions = positions;
            }
          );
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
    }, [workflow, flow, placeholders]);

    useEffect(() => {
      const updatedModel = updateSelectionStyles(model, selection);
      setModel(updatedModel);
    }, [selection]);

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
        if (event.target.classList?.contains('react-flow__pane')) {
          cancelPlaceholder();
          updateSelection(null);
        }
      },
      [updateSelection]
    );

    // Trigger a fit when the parent div changes size
    useEffect(() => {
      if (flow && ref) {
        let isFirstCallback = true;

        const throttledResize = throttle(() => {
          flow.fitView({ duration: FIT_DURATION, padding: FIT_PADDING });
        }, FIT_DURATION * 2);

        const resizeOb = new ResizeObserver(function (entries) {
          if (!isFirstCallback) {
            // Don't fit when the listener attaches (it callsback immediately)
            throttledResize();
          }
          isFirstCallback = false;
        });
        resizeOb.observe(ref);

        return () => {
          throttledResize.cancel();
          resizeOb.unobserve(ref);
        };
      }
    }, [flow, ref]);

    const connectHandlers = useConnect(model, setModel, store);

    return (
      <ReactFlowProvider>
        <ReactFlow
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
          <Controls showInteractive={false} position="bottom-left">
            <ControlButton
              onClick={() => {
                setAutofit(!autofit);
              }}
              title="Automatically fit view"
            >
              <ViewfinderCircleIcon style={{ opacity: autofit ? 1 : 0.4 }} />
            </ControlButton>
          </Controls>
        </ReactFlow>
      </ReactFlowProvider>
    );
  }
);
