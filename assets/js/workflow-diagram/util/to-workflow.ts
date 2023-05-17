import { Lightning, Flow } from '../types';

// This converts an internal react flow model back to a Lighting representation
// Used for diffing when something changes
// TODO how strict does this need to be? Can we lose information through this?
// I think the store means we can be flexible and only convert stuff we want to edit
// (stuff like body and adaptor we can ignore)
const model = (model: Flow.Model) => {
  const workflow: Lightning.Workflow = {
    // What about the id? Do we need it? Did we lose it?
    triggers: [],
    jobs: [],
    edges: [],
  };

  model.nodes.forEach(node => {
    const wfNode: Partial<Lightning.Node> = {
      id: node.id,
      name: node.data?.name,
      // TODO workflow id?
    };

    if (node.type === 'trigger') {
      // TODO
      workflow.triggers.push(wfNode as Lightning.TriggerNode);
    } else {
      workflow.jobs.push(wfNode as Lightning.JobNode);
    }
  });

  model.edges.forEach(edge => {
    const source = model.nodes.find(({ id }) => id === edge.source);

    const wfEdge: Partial<Lightning.Edge> = {
      id: edge.id,
      target_job_id: edge.target,
    };

    if (source && source.type === 'trigger') {
      wfEdge.source_trigger_id = edge.source;
    } else {
      wfEdge.source_job_id = edge.source;
    }

    workflow.edges.push(wfEdge as Lightning.Edge);
  });

  return workflow;
};

export default model;
