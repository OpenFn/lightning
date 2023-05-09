import { Node, Workflow } from '../types';

// adds a placeholder node as child of the target
// A node can only have one placeholder at a time
// We show the new job form and when the job is actually
// created, we replace the placeholder with the real thing

// Model is a react-flow chart model
export const add = (model: any, node: Node) => {
  const newModel: any = {
    nodes: [],
    edges: [],
  };

  const id = crypto.randomUUID();
  newModel.nodes.push({
    id,
    position: node.position,
    placeholder: true,
  });
  newModel.edges.push({
    id: `${node.id}-${id}`,
    source: node.id,
    target: id,
    placeholder: true,
  });
  return newModel;
};

// Do we have a placeholder associated with this node?
export const exists = (model: any, node: Node) => {};

export const isPlaceholder = (node: Node) => node.placeholder;

// Conver a node from a placeholder to a normal node
// Assign it a UUID
export const convert = (model: any) => {};
