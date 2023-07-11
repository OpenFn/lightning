import { Flow } from '../types';
import { WorkflowProps } from '../workflow-editor/store';

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

type Workflow = Pick<WorkflowProps, 'jobs' | 'edges' | 'triggers'>;

// Identify placeholder nodes and return a new workflow model
export const identify = (store: Workflow) => {
  const { jobs, triggers, edges } = store;

  const newJobs = jobs.map(item => {
    if (!item.name && !item.body) {
      return {
        ...item,
        placeholder: true,
      };
    }
    return item;
  });

  const newEdges = edges.map(edge => {
    const target = newJobs.find(({ id }) => edge.target_job_id === id);
    if (target?.placeholder) {
      return {
        ...edge,
        placeholder: true,
      };
    }
    return edge;
  });

  const result = {
    triggers,
    jobs: newJobs,
    edges: newEdges,
  };

  return result;
};
