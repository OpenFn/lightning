import { useCallback } from 'react';
import { useStore, StoreApi } from 'zustand';
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

const setDropTargets = (model: Flow.Model, source: string) => {
  const newModel = {
    nodes: model.nodes.map(n => ({
      ...n,
      data: {
        ...n.data,
        // TODO: don't allow drops on upstream nodes (circular dependenccies)
        // TODO don't allow targets that are already connected
        isValidDropTarget: n.id !== source && n.type === 'job',
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
      setModel(setDropTargets(model, args.nodeId));
    },
    [model]
  );

  const onConnectEnd = useCallback(
    (evt, args) => {
      setModel(resetModel(model));
    },
    [model]
  );

  return { onConnect, onConnectStart, onConnectEnd };
};
