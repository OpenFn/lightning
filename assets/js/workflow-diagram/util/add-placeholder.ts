import { Node } from '../types';

// adds a placeholder node as child of the target
// A node can only have one placeholder at a time
// We show the new job form and when the job is actually
// created, we replace the placeholder with the real thing
export const add = (model: any, node: Node) => {
  const newModel = {
    nodes: [] as any[],
    edges: [] as any[],
  };

  const id = `${node.id}-placeholder`;
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

// Do we have a placeholder associated with this node?
export const exists = (model: any, node: Node) => {};

export const isPlaceholder = (node: Node) => node.id.match(/-placeholder$/);

// Conver a node from a placeholder to a normal node
// Assign it a UUID
export const convert = (model: any) => {};
