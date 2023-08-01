import { styleEdge } from '../styles';
import { Flow } from '../types';
// import { WorkflowProps } from '../workflow-editor/store';

// adds a placeholder node as child of the target
// A node can only have one placeholder at a time
// We show the new job form and when the job is actually
// created, we replace the placeholder with the real thing

// Model is a react-flow chart model
export const add = (_model: Flow.Model, parentNode: Flow.Node) => {
  const newModel: Flow.Model = {
    nodes: [],
    edges: [],
  };

  const targetId = crypto.randomUUID();
  newModel.nodes.push({
    id: targetId,
    type: 'placeholder',
    position: {
      // Offset the position of the placeholder to be more pleasing during animation
      x: parentNode.position.x,
      y: parentNode.position.y + 100,
    },
    data: {
      body: '// hello world',
    },
  });

  newModel.edges.push(
    styleEdge({
      id: crypto.randomUUID(),
      type: 'step',
      source: parentNode.id,
      target: targetId,
      data: { condition: 'on_job_success', placeholder: true },
    })
  );

  return newModel;
};

// export const isPlaceholder = (node: Node) => node.placeholder;

// type Workflow = Pick<WorkflowProps, 'jobs' | 'edges' | 'triggers'>;

// // Identify placeholder nodes and return a new workflow model
// export const identify = (store: Workflow) => {
//   const { jobs, triggers, edges } = store;

//   const newJobs = jobs.map(item => {
//     if (!item.name && !item.body) {
//       return {
//         ...item,
//         placeholder: true,
//       };
//     }
//     return item;
//   });

//   const newEdges = edges.map(edge => {
//     const target = newJobs.find(({ id }) => edge.target_job_id === id);
//     if (target?.placeholder) {
//       return {
//         ...edge,
//         placeholder: true,
//       };
//     }
//     return edge;
//   });

//   const result = {
//     triggers,
//     jobs: newJobs,
//     edges: newEdges,
//   };

//   return result;
// };
