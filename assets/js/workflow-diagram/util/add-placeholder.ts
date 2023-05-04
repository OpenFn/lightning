import { Node } from '../types';

// adds a placeholder node as child of the target
// A node can only have one placeholder at a time
// We show the new job form and when the job is actually
// created, we replace the placeholder with the real thing
export default (model, node: Node) => {
  console.log(model);
  const newModel = {
    nodes: [...model.nodes],
    edges: [...model.edges],
  };

  const id = `${node.id}-placeholder`;
  newModel.nodes.push({
    id,
    type: 'job',
    data: {
      label: 'New Job',
    },
    position: node.position,
  });
  newModel.edges.push({
    id: `${node.id}-${id}`,
    source: node.id,
    target: id,
  });
  return newModel;
};
