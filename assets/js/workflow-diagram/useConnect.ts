import { useCallback } from 'react';

const updateModel = (model, source: string) => {
  console.log('update model');
  const newModel = {
    nodes: model.nodes.map(n => ({
      ...n,
      data: {
        ...n.data,
        // TODO: don't allow drops on upstream nodes (circular dependenccies)
        isValidDropTarget: n.id !== source && n.type === 'job',
      },
    })),
    edges: model.edges,
  };

  return newModel;
};

const resetModel = model => ({
  nodes: model.nodes.map(n => ({
    ...n,
    data: {
      ...n.data,
      isValidDropTarget: false,
    },
  })),
  edges: model.edges,
});

export default (model, setModel) => {
  const onConnect = useCallback(args => {
    console.log('CONNECT', args);
  }, []);

  const onConnectStart = useCallback(
    (_evt, args) => {
      console.log('CONNECT START', args);
      console.log(model);
      setModel(updateModel(model, args.nodeId));
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
