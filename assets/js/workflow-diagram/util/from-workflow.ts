import { Node, Edge, Workflow } from '../types';

type Positions = Record<string, { x: number; y: number }>;

// TODO pass in the currently selected items so that we can maintain selection
const fromWorkflow = (
  workflow: Workflow,
  positions: Positions,
  selectedNodeId?: string
) => {
  if (workflow.jobs.length == 0) {
    return { nodes: [], edges: [] };
  }

  const process = (
    items: Array<Node | Edge>,
    collection: any[],
    type: 'job' | 'trigger' | 'edge'
  ) => {
    items.forEach(item => {
      const model: any = {
        id: item.id,
        // className: 'nodrag', // prevent selection
        // selectable: false,
      };
      if (item.id === selectedNodeId) {
        model.selected = true;
      }
      if (/(job|trigger)/.test(type)) {
        model.type = type;

        if (positions && positions[item.id]) {
          model.position = positions[item.id];
        }
      } else {
        let edge = item as Edge;
        model.source = edge.source_trigger_id || edge.source_job_id;
        model.target = edge.target_job_id;
        model.label = item.label;
        model.labelBgStyle = {
          fill: 'rgb(243, 244, 246)',
        };
      }

      model.data = {
        ...item,
        label: item.label || item.id,
        // TMP
        trigger: {
          type: 'webhook',
        },
      };
      collection.push(model);
    });
  };

  const nodes = [] as any[];
  const edges = [] as any[];

  process(workflow.jobs, nodes, 'job');
  process(workflow.triggers, nodes, 'trigger');
  process(workflow.edges, edges, 'edge');

  return { nodes, edges };
};

export default fromWorkflow;
