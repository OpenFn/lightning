import { Workflow } from '../types';

const model = model => {
  const workflow: Workflow = {
    triggers: [],
    jobs: [],
    edges: [],
  };

  model.nodes.forEach(node => {
    const wfNode = {
      id: node.id,
    };
    if (node.type === 'trigger') {
      workflow.triggers.push(wfNode);
    } else {
      workflow.jobs.push(wfNode);
    }
  });
  model.edges.forEach(edge => {
    const source = model.nodes.find(({ id }) => id === edge.source);

    const wfEdge = {
      id: edge.id,
      target_job_id: edge.target,
    };

    if (source && source.type === 'trigger') {
      wfEdge.source_trigger_id = edge.source;
      wfEdge.trigger = edge.data.trgger || {};
    } else {
      wfEdge.source_job_id = edge.source;
    }

    workflow.edges.push(wfEdge);
  });

  return workflow;
};

export default model;
