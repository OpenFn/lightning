import { Lightning, Flow } from '../types';

// adds a placeholder node as child of the target
// A node can only have one placeholder at a time
// We show the new job form and when the job is actually
// created, we replace the placeholder with the real thing

// Model is a react-flow chart model
export const add = (model: Flow.Model, node: Flow.Node) => {
  const newModel: any = {
    nodes: [],
    edges: [],
  };

  const id = crypto.randomUUID();
  newModel.nodes.push({
    id,
    position: node.position,
  });
  newModel.edges.push({
    id: `${node.id}-${id}`,
    source: node.id,
    target: id,
  });
  return newModel;
};

export const isPlaceholder = (node: Node) => node.placeholder;
