import { useCallback, useState } from 'react';
import { useStore, StoreApi } from 'zustand';
import { getIncomers } from 'reactflow';
import { styleEdge } from './styles';
import { Flow } from './types';
import { WorkflowState } from '../workflow-editor/store';
import toWorkflow from './util/to-workflow';

const generateEdgeDiff = (source: string, target: string) => {
  const newEdge = styleEdge({
    id: 'NEW' ?? crypto.randomUUID(),
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

const setValidDropTargets = (model: Flow.Model, source: string) => {
  const newModel = {
    nodes: model.nodes.map(n => ({
      ...n,
      data: {
        ...n.data,
        isValidDropTarget:
          n.id !== source &&
          n.type === 'job' &&
          // Don't allow linking to direct ancestors, as it'll cause a loop
          !isUpstream(model, n.id, source) &&
          // Don't allow an edge to be created if it exists
          !isChild(model, source, n.id),
      },
    })),
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

    // TODO this doesn't seem to save right now?
    console.log('WARNING: changes are not saved');
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

  const onNodeMouseEnter = (evt, args) => {
    if (dragActive) {
      setModel(setActiveDropTarget(model, args.id));
    }
  };

  const onNodeMouseLeave = (evt, args) => {
    if (dragActive) {
      setModel(setActiveDropTarget(model, ''));
    }
  };

  return {
    onConnect,
    onConnectStart,
    onConnectEnd,
    onNodeMouseEnter,
    onNodeMouseLeave,
  };
};
