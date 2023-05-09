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
      label: node.data?.label,
    };
    if (node.placeholder) {
      // TODO this is a transient property, should not persist. I think?
      // If we don't persist, and the id doesn't use a convention (because changing id on the fly causes bigtime issues)
      // How do we recognise a saved placeholder?
      // Well I guess we can infer it if there's no label or expression
      wfNode.placeholder = true;
    }

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

    if (edge.placeholder) {
      // TODO this is a transient property, should not persist. I think?
      // If we don't persist, and the id doesn't use a convention (because changing id on the fly causes bigtime issues)
      // How do we recognise a saved placeholder?
      // Well I guess we can infer it if there's no label or expression
      wfEdge.placeholder = true;
    }

    if (source && source.type === 'trigger') {
      wfEdge.source_trigger_id = edge.source;
      wfEdge.trigger = edge.data.trigger || {};
    } else {
      wfEdge.source_job_id = edge.source;
    }

    workflow.edges.push(wfEdge);
  });

  return workflow;
};

export default model;
