import { Flow } from '../types';

// adds a placeholder node as child of the target
// A node can only have one placeholder at a time
// We show the new job form and when the job is actually
// created, we replace the placeholder with the real thing

// Model is a react-flow chart model
export const add = (_model: Flow.Model, parentNode: Flow.Node) => {
  const newModel: any = {
    nodes: [],
    edges: [],
  };

  const targetId = crypto.randomUUID();
  newModel.nodes.push({
    id: targetId,
    position: parentNode.position,
  });

  newModel.edges.push({
    id: crypto.randomUUID(),
    source: parentNode.id,
    target: targetId,
  });
  return newModel;
};

export const isPlaceholder = (node: Node) => node.placeholder;
