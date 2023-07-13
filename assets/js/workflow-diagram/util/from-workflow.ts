import { NODE_HEIGHT, NODE_WIDTH } from '../constants';
import { Lightning, Flow, Positions } from '../types';
import { identify, isPlaceholder } from './placeholder';

function getEdgeLabel(condition: string) {
  if (condition) {
    console.log(condition);
    if (condition === 'on_job_success') {
      return '✓';
    }
    if (condition === 'on_job_failure') {
      return 'X';
    }
    if (condition === 'always') {
      return '∞';
    }
    // some code expression
    return '{}';
  }
}

// TODO separate structural stuff (labels, selected, position)
// from style stuff, and move the style functions somewhere obvious
const fromWorkflow = (
  workflow: Lightning.Workflow,
  positions: Positions,
  selectedNodeId?: string
): Flow.Model => {
  if (workflow.jobs.length == 0) {
    return { nodes: [], edges: [] };
  }
  const workflowWithPlaceholders = identify(workflow);
  const allowPlaceholder = workflowWithPlaceholders.jobs.every(
    j => !isPlaceholder(j)
  );

  const process = (
    items: Array<Lightning.Node | Lightning.Edge>,
    collection: Array<Flow.Node | Flow.Edge>,
    type: 'job' | 'trigger' | 'edge'
  ) => {
    items.forEach(item => {
      const model: any = {
        id: item.id,
        data: {
          ...item,
        },
      };

      if (item.id === selectedNodeId) {
        model.selected = true;
      } else {
        model.selected = false;
      }

      if (/(job|trigger)/.test(type)) {
        const node = item as Lightning.Node;
        model.type = isPlaceholder(node) ? 'placeholder' : type;

        if (positions && positions[node.id]) {
          model.position = positions[node.id];
        }

        // This is a work of fantasy
        // model.width = NODE_WIDTH;
        // model.height = NODE_HEIGHT;

        model.data.allowPlaceholder = allowPlaceholder;

        if (type === 'trigger') {
          model.data.trigger = {
            type: (node as Lightning.TriggerNode).type,
          };
        }
      } else {
        const edge = item as Lightning.Edge;
        model.source = edge.source_trigger_id || edge.source_job_id;
        model.target = edge.target_job_id;
        // TODO I don't like all this style stuff being buried in this file
        // Feels like hte wrong place for cosmetic stuff
        // model.labelBgStyle = {
        //   fill: 'rgb(243, 244, 246)',
        // };
        model.type = 'step';
        model.markerEnd = {
          type: 'arrowclosed',
          width: 32,
          height: 32,
        };
        if (isPlaceholder(item)) {
          model.style = {
            strokeDasharray: '4, 4',
            stroke: 'rgb(99, 102, 241, 0.3)',
            strokeWidth: '1.5px',
          };
        }
        // all edge labels are circles
        // with tick, cross, infinity or {}
        model.label = getEdgeLabel(edge.condition);
        model.labelBgPadding = [12, 8];
        model.labelBgStyle = {
          stroke: '#b1b1b7',
          strokeWidth: 2,
          fill: 'white',
        };
        model.labelBgBorderRadius = 16;
      }

      collection.push(model);
    });
  };

  const nodes = [] as Flow.Node[];
  const edges = [] as Flow.Edge[];

  process(workflowWithPlaceholders.jobs, nodes, 'job');
  process(workflowWithPlaceholders.triggers, nodes, 'trigger');
  process(workflowWithPlaceholders.edges, edges, 'edge');
  return { nodes, edges };
};

export default fromWorkflow;
