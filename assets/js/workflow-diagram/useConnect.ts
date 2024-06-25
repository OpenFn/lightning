import { useCallback, useState } from 'react';
import { useStore, StoreApi } from 'zustand';
import Connection from './edges/Connection';
import { styleEdge } from './styles';
import { Flow } from './types';
import { WorkflowState } from '../workflow-editor/store';
import toWorkflow from './util/to-workflow';

const generateEdgeDiff = (source: string, target: string) => {
  const newEdge = styleEdge({
    id: crypto.randomUUID(),
    type: 'step',
    source,
    target,
    data: {
      enabled: true,
      condition_type: 'on_job_success',
    },
  });

  // this is just a diff
  const updatedModel = {
    nodes: [],
    edges: [newEdge],
  };

  return updatedModel;
};

// Returns true if nodeInQuestion is a descendant of the root
// TODO memoise this
const isUpstream = (
  model: Flow.Model,
  parent: string,
  nodeInQuestion: string
) => {
  // walk down the graph from parent, return true if we ever hit the node in question
  const edges = model.edges.filter(e => e.source === parent);
  for (const edge of edges) {
    if (
      edge.target === nodeInQuestion ||
      isUpstream(model, edge.target, nodeInQuestion)
    ) {
      return true;
    }
  }
  return false;
};
const isChild = (model: Flow.Model, sourceNode: string, targetNode: string) => {
  const edges = model.edges.filter(e => e.source === sourceNode);

  return edges.find(e => e.target === targetNode);
};

const getDropTargetError = (
  model: Flow.Model,
  source: string,
  target: string
) => {
  if (target === source) {
    return true;
  }
  const targetNode = model.nodes.find(n => n.id === target);

  if (targetNode?.type === 'trigger') {
    return 'Cannot connect to a trigger';
  }

  if (isUpstream(model, target, source)) {
    // Don't allow linking to direct ancestors, as it'll cause a loop
    return 'Cannot create circular workflow';
  }

  if (isChild(model, source, target)) {
    // Don't allow an edge to be created if it exists
    return 'Already connected to this step';
  }
};

const setValidDropTargets = (model: Flow.Model, source: string) => {
  const newModel = {
    nodes: model.nodes.map(n => {
      const err = getDropTargetError(model, source, n.id);
      return {
        ...n,
        data: {
          ...n.data,
          isValidDropTarget: !err,
          dropTargetError: err,
        },
      };
    }),
    edges: model.edges,
  };
  return newModel;
};

const setActiveDropTarget = (model: Flow.Model, target: string) => {
  const newModel = {
    nodes: model.nodes.map(n => ({
      ...n,
      data: {
        ...n.data,
        isActiveDropTarget: n.id === target,
      },
    })),
    edges: model.edges,
  };

  return newModel;
};

const resetModel = (model: Flow.Model) => ({
  nodes: model.nodes.map(n => ({
    ...n,
    data: {
      ...n.data,
      isValidDropTarget: false,
      isActiveDropTarget: false,
    },
  })),
  edges: model.edges,
});

export default (
  model: Flow.Model,
  setModel,
  store: StoreApi<WorkflowState>
) => {
  const [dragActive, setDragActive] = useState<string | false>(false);

  const addToStore = useStore(store!, state => state.add);

  const onConnect = useCallback(args => {
    const newModel = generateEdgeDiff(args.source, args.target);
    const wf = toWorkflow(newModel);

    addToStore(wf);
  }, []);

  const onConnectStart = useCallback(
    (_evt, args) => {
      setDragActive(args.nodeId);
      setModel(setValidDropTargets(model, args.nodeId));
    },
    [model]
  );

  const onConnectEnd = useCallback(
    (evt, args) => {
      setDragActive(false);
      setModel(resetModel(model));
    },
    [model]
  );

  const onNodeMouseEnter = useCallback(
    (evt, args) => {
      if (dragActive) {
        setModel(setActiveDropTarget(model, args.id));
      }
    },
    [model]
  );

  const onNodeMouseLeave = useCallback(
    (evt, args) => {
      if (dragActive) {
        setModel(setActiveDropTarget(model, ''));
      }
    },
    [model]
  );

  const isValidConnection = useCallback(
    ({ source, target }: { target: string }) => {
      // this is accessing a stale model :( why?
      // const targetNode = model.nodes.find(e => e.id === target);
      // return targetNode?.data.isValidDropTarget;

      // it'll work suboptimally if we duplicate the validation test
      // This fires a lot so its super annoying
      const err = getDropTargetError(model, source, target);
      return !err;
    },
    [model]
  );

  return {
    connectionLineComponent: Connection,
    onConnect,
    onConnectStart,
    onConnectEnd,
    onNodeMouseEnter,
    onNodeMouseLeave,
    isValidConnection,
  };
};
