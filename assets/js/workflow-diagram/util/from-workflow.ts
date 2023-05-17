import { NODE_HEIGHT, NODE_WIDTH } from '../constants';
import { Node, Edge, Workflow } from '../types';
import { isPlaceholder } from './add-placeholder';

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
  const allowPlaceholder = workflow.jobs.every(j => !isPlaceholder(j));

  const process = (
    items: Array<Node | Edge>,
    collection: any[],
    type: 'job' | 'trigger' | 'edge'
  ) => {
    items.forEach(item => {
      const model: any = {
        id: item.id,
        data: {
          name: item.name,
          item: item,
        },
      };

      if (item.id === selectedNodeId) {
        model.selected = true;
      }
      if (/(job|trigger)/.test(type)) {
        model.type = isPlaceholder(item) ? 'placeholder' : type;

        if (positions && positions[item.id]) {
          model.position = positions[item.id];
        }

        model.width = NODE_WIDTH;
        model.height = NODE_HEIGHT;

        model.data.allowPlaceholder = allowPlaceholder;

        if (type === 'trigger') {
          model.data.trigger = {
            type: item.type,
          };
        }
      } else {
        let edge = item as Edge;
        model.source = edge.source_trigger_id || edge.source_job_id;
        model.target = edge.target_job_id;
        model.label = item.name;
        model.labelBgStyle = {
          fill: 'rgb(243, 244, 246)',
        };
        if (isPlaceholder(item)) {
          model.style = {
            strokeDasharray: '4, 4',
            stroke: 'rgb(99, 102, 241, 0.3)',
            strokeWidth: '1.5px',
          };
        }
      }

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
