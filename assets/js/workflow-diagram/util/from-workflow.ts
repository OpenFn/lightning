import { Lightning, Flow, Positions } from '../types';
// import { identify, isPlaceholder } from './placeholder';
import { styleEdge } from '../styles';

function getEdgeLabel(condition: string) {
  if (condition) {
    if (condition === 'on_job_success') {
      return '✓';
    }
    if (condition === 'on_job_failure') {
      return 'X';
    }
    if (condition === 'always') {
      return '∞';
    }
  }
  // some code expression
  return '{}';
}

const fromWorkflow = (
  workflow: Lightning.Workflow,
  positions: Positions,
  placeholders: Flow.Model = { nodes: [], edges: [] },
  selectedId?: string
): Flow.Model => {
  // const workflowWithPlaceholders = identify(workflow);
  // const allowPlaceholder = workflowWithPlaceholders.jobs.every(
  //   j => !isPlaceholder(j)
  // );
  const allowPlaceholder = placeholders.nodes.length === 0;

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

      if (item.id === selectedId) {
        model.selected = true;
      } else {
        model.selected = false;
      }

      if (/(job|trigger)/.test(type)) {
        const node = item as Lightning.Node;
        model.type = type;

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
        model.type = 'step';
        model.label = getEdgeLabel(edge.condition);
        model.markerEnd = {
          type: 'arrowclosed',
          width: 32,
          height: 32,
        };
        model.data = { condition: edge.condition };
        styleEdge(model);
      }

      collection.push(model);
    });
  };

  const nodes = [
    ...placeholders.nodes.map(n => {
      if (selectedId == n.id) {
        n.selected = true;
      }
      return n;
    }),
  ] as Flow.Node[];
  const edges = [...placeholders.edges] as Flow.Edge[];

  process(workflow.jobs, nodes, 'job');
  process(workflow.triggers, nodes, 'trigger');
  process(workflow.edges, edges, 'edge');

  return { nodes, edges };
};

export default fromWorkflow;
