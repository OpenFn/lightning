import React, {
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import ReactFlow, {
  NodeChange,
  ReactFlowInstance,
  ReactFlowProvider,
  applyNodeChanges,
} from 'reactflow';
import { DEFAULT_TEXT } from '../editor/Editor';
import layout from './layout';
import nodeTypes from './nodes';
import fromWorkflow from './util/from-workflow';
import * as placeholder from './util/placeholder';
import throttle from './util/throttle';
import toWorkflow from './util/to-workflow';

import { useStore } from 'zustand';
import { shallow } from 'zustand/shallow';
import { WorkflowContext } from '../workflow-editor/component';

import { FIT_DURATION, FIT_PADDING } from './constants';
import type { Flow, Positions } from './types';

type WorkflowDiagramProps = {
  onSelectionChange: (id?: string) => void;
};

type ChartCache = {
  positions: Positions;
  selectedId?: string;
  ignoreNextSelection: boolean;
  deferSelection?: string;
};

// This will take a store passed from the server and do some light transformation
// Specifically it identifies placeholder nodes

export default React.forwardRef<HTMLElement, WorkflowDiagramProps>(
  (props, ref) => {
    const workflowStore = useContext(WorkflowContext);

    const add = useStore(workflowStore!, state => state.add);
    const remove = useStore(workflowStore!, state => state.remove);
    const change = useStore(workflowStore!, state => state.change);

    const storeModel = useStore(
      workflowStore!,
      state => ({
        jobs: state.jobs,
        triggers: state.triggers,
        edges: state.edges,
      }),
      shallow
    );

    const workflow = useMemo(
      () => placeholder.identify(storeModel),
      [storeModel]
    );

    const { onSelectionChange } = props;
    const [model, setModel] = useState<Flow.Model>({ nodes: [], edges: [] });

    // Track positions and selection on a ref, as a passive cache, to prevent re-renders
    // If I push the store in here and use it more, will I have to do this less...?
    const chartCache = useRef<ChartCache>({
      positions: {},
      selectedId: undefined,
      ignoreNextSelection: false,
    });

    const [flow, setFlow] = useState<ReactFlowInstance>();

    const setFlowInstance = useCallback(
      (s: ReactFlowInstance) => {
        setFlow(s);
      },
      [setFlow]
    );

    // Respond to changes pushed into the component from outside
    // This usually means the workflow has changed or its the first load, so we don't want to animate
    // Later, if responding to changes from other users live, we may want to animate
    useEffect(() => {
      const { positions, selectedId } = chartCache.current;
      const newModel = fromWorkflow(workflow, positions, selectedId);

      console.debug('UPDATING WORKFLOW', newModel, selectedId);
      if (flow && newModel.nodes.length) {
        layout(newModel, setModel, flow, 200).then(positions => {
          // trigger selection on new nodes once they've been passed back through to us
          if (chartCache.current.deferSelection) {
            onSelectionChange(chartCache.current.deferSelection);
            delete chartCache.current.deferSelection;
          }

          // Bit of a hack - don't update positions until the animation has finished
          chartCache.current.positions = positions;
        });
      } else {
        chartCache.current.positions = {};
      }
    }, [chartCache, workflow, flow]);

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
          addNode(node);
        }
      },
      [model]
    );

    const addNode = useCallback(
      (parentNode: Flow.Node) => {
        // Generate a placeholder node and edge
        const diff = placeholder.add(model, parentNode);

        // reactflow will fire a selection change event after the click
        // (regardless of whether the node is selected)
        // We need to ignore this
        chartCache.current.ignoreNextSelection = true;

        // If the editor is currently open, update the selection to show the new node
        if (chartCache.current.selectedId) {
          chartCache.current.deferSelection = diff.nodes[0].id;
        }

        // Mark the new node as selected for the next render
        chartCache.current.selectedId = diff.nodes[0].id;

        // Push the changes
        add(toWorkflow(diff));
      },
      [add, model]
    );

    const commitPlaceholder = useCallback(
      (evt: CustomEvent<any>) => {
        const { id, name } = evt.detail;
        // Select the placeholder on next render
        chartCache.current.deferSelection = id;

        // Update the store
        change({
          jobs: [{ id, name, body: DEFAULT_TEXT }],
        });
      },
      [change, workflow]
    );

    const cancelPlaceholder = useCallback(
      (evt: CustomEvent<any>) => {
        const { id } = evt.detail;

        const e = model.edges.find(({ target }) => target === id);
        remove({ jobs: [id], edges: [e?.id] });
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
    }, [commitPlaceholder, ref]);

    // Note that we only support a single selection
    const handleSelectionChange = useCallback(
      ({ nodes, edges }: Flow.Model) => {
        // console.log('> handleSelectionChange', nodes.map(({ id }) => id))
        const { selectedId, ignoreNextSelection } = chartCache.current;
        const newSelectedId = nodes.length
          ? nodes[0].id
          : edges.length
          ? edges[0].id
          : undefined;
        if (ignoreNextSelection) {
          console.log('ignoring selection change');

          // do nothing as the ignore flag was set
        } else if (newSelectedId !== selectedId) {
          chartCache.current.selectedId = newSelectedId;
          onSelectionChange(newSelectedId);
        }
        chartCache.current.ignoreNextSelection = false;
      },
      [onSelectionChange]
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

    return (
      <ReactFlowProvider>
        <ReactFlow
          proOptions={{ account: 'paid-pro', hideAttribution: true }}
          nodes={model.nodes}
          edges={model.edges}
          onSelectionChange={handleSelectionChange}
          onNodesChange={onNodesChange}
          nodesDraggable={false}
          nodeTypes={nodeTypes}
          onNodeClick={handleNodeClick}
          onInit={setFlowInstance}
          deleteKeyCode={null}
          fitView
          fitViewOptions={{ padding: FIT_PADDING }}
        />
      </ReactFlowProvider>
    );
  }
);
