import React, { useCallback, useEffect, useRef, useState } from 'react';
import ReactFlow, {
  NodeChange,
  ReactFlowInstance,
  ReactFlowProvider,
  applyNodeChanges,
} from 'reactflow';
import { useStore, StoreApi } from 'zustand';
import { shallow } from 'zustand/shallow';

import { DEFAULT_TEXT } from '../editor/Editor';
import layout from './layout';
import nodeTypes from './nodes';
import edgeTypes from './edges';
import fromWorkflow from './util/from-workflow';
import * as placeholder from './util/placeholder';
import throttle from './util/throttle';
import toWorkflow from './util/to-workflow';
import updateSelectionStyles from './util/update-selection';
import { FIT_DURATION, FIT_PADDING } from './constants';
import shouldLayout from './util/should-layout';

import type { WorkflowState } from '../workflow-editor/store';
import type { Flow, Positions } from './types';

type WorkflowDiagramProps = {
  onSelectionChange: (id?: string) => void;
  store: StoreApi<WorkflowState>;
  initialSelection?: string | null;
};

type ChartCache = {
  positions: Positions;
  selectedId?: string;
  lastLayout?: string;
};

export default React.forwardRef<HTMLElement, WorkflowDiagramProps>(
  (props, ref) => {
    const { onSelectionChange, store, initialSelection } = props;

    const add = useStore(store!, state => state.add);
    const remove = useStore(store!, state => state.remove);
    const change = useStore(store!, state => state.change);

    const workflow = useStore(
      store!,
      state => ({
        jobs: state.jobs,
        triggers: state.triggers,
        edges: state.edges,
      }),
      shallow
    );
    const [model, setModel] = useState<Flow.Model>({ nodes: [], edges: [] });

    // Track positions and selection on a ref, as a passive cache, to prevent re-renders
    const chartCache = useRef<ChartCache>({
      positions: {},
      selectedId: initialSelection,
      lastLayout: undefined,
    });

    const [flow, setFlow] = useState<ReactFlowInstance>();

    // Respond to changes pushed into the component from outside
    // This usually means the workflow has changed or its the first load, so we don't want to animate
    // Later, if responding to changes from other users live, we may want to animate
    useEffect(() => {
      const { positions, selectedId } = chartCache.current;
      const newModel = fromWorkflow(workflow, positions, selectedId);
      //console.log('UPDATING WORKFLOW', newModel, selectedId);
      if (flow && newModel.nodes.length) {
        const layoutId = shouldLayout(
          newModel.edges,
          chartCache.current.lastLayout
        );

        if (layoutId) {
          chartCache.current.lastLayout = layoutId;
          layout(newModel, setModel, flow, 300).then(positions => {
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
    }, [workflow, flow]);

    const onNodesChange = useCallback(
      (changes: NodeChange[]) => {
        const newNodes = applyNodeChanges(changes, model.nodes);
        setModel({ nodes: newNodes, edges: model.edges });
      },
      [setModel, model]
    );

    const updateSelection = useCallback(
      (id?: string) => {
        const { selectedId } = chartCache.current;
        if (id !== selectedId) {
          chartCache.current.selectedId = id;
          onSelectionChange(id);

          const updatedModel = updateSelectionStyles(model, id);
          setModel(updatedModel);
        }
      },
      [onSelectionChange, model]
    );

    const handleNodeClick = useCallback(
      (event: React.MouseEvent, node: Flow.Node) => {
        if ((event.target as HTMLElement).closest('[name=add-node]')) {
          addNode(node);
        } else {
          updateSelection(node.id);
        }
      },
      [updateSelection]
    );

    const handleEdgeClick = useCallback(
      (_event: React.MouseEvent, edge: Flow.Edge) => {
        updateSelection(edge.id);
      },
      [updateSelection]
    );

    const handleBackgroundClick = useCallback(
      (event: React.MouseEvent) => {
        if (
          event.target.classList &&
          event.target.classList.contains('react-flow__pane')
        ) {
          updateSelection(undefined);
        }
      },
      [updateSelection]
    );

    const addNode = useCallback(
      (parentNode: Flow.Node) => {
        // Generate a placeholder node and edge
        const diff = placeholder.add(model, parentNode);
        const [newNode] = diff.nodes;
        // Ensure the starting position is set
        chartCache.current.positions[newNode.id] = newNode.position;
        // Mark the new node as selected for the next render
        chartCache.current.selectedId = newNode.id;
        onSelectionChange(newNode.id);

        // Push the changes
        add(toWorkflow(diff));
      },
      [add, model]
    );

    const commitPlaceholder = useCallback(
      (evt: CustomEvent<any>) => {
        const { id, name } = evt.detail;

        // Update the store
        change({
          jobs: [{ id, name, body: DEFAULT_TEXT }],
        });

        onSelectionChange(id);
      },
      [change]
    );

    const cancelPlaceholder = useCallback(
      (evt: CustomEvent<any>) => {
        const { id } = evt.detail;

        const e = model.edges.find(({ target }) => target === id);
        remove({ jobs: [id], edges: [e?.id] });
        onSelectionChange(undefined);
      },
      [remove, model]
    );

    useEffect(() => {
      if (ref) {
        ref.addEventListener<any>('commit-placeholder', commitPlaceholder);
        ref.addEventListener<any>('cancel-placeholder', cancelPlaceholder);

        return () => {
          if (ref) {
            ref.removeEventListener<any>(
              'commit-placeholder',
              commitPlaceholder
            );
            ref.removeEventListener<any>(
              'cancel-placeholder',
              cancelPlaceholder
            );
          }
        };
      }
    }, [commitPlaceholder, cancelPlaceholder, ref]);

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
        />
      </ReactFlowProvider>
    );
  }
);
