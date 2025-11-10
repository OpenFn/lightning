import type { RunInfo, RunStep } from '../../workflow-store/store';
import { NODE_HEIGHT, NODE_WIDTH } from '../constants';
import {
  sortOrderForSvg,
  styleEdge,
  styleNode,
  edgeLabelIconStyles,
  edgeLabelTextStyles,
} from '../styles';
import type { Lightning, Flow, Positions } from '../types';

function getEdgeLabel(edge: Lightning.Edge) {
  let label: string | JSX.Element = '{ }';

  switch (edge.condition_type) {
    case 'on_job_success':
      label = '✓';
      break;
    case 'on_job_failure':
      label = 'X';
      break;
    case 'always':
      label = '∞';
      break;
  }
  const { condition_label } = edge;

  const result = [
    <span
      key={`${edge.id}-icon`}
      style={edgeLabelIconStyles(edge.condition_type)}
    >
      {label}
    </span>,
  ];

  if (condition_label) {
    const l =
      condition_label.length > 22
        ? condition_label.slice(0, 22) + '...'
        : condition_label;
    result.push(
      <span key={`${edge.id}-label`} style={edgeLabelTextStyles}>
        {l}
      </span>
    );
  }

  return result;
}

const fromWorkflow = (
  workflow: Lightning.Workflow,
  positions: Positions,
  placeholders: Flow.Model = { nodes: [], edges: [] },
  runSteps: RunInfo,
  selectedId: string | null
): Flow.Model => {
  const allowPlaceholder =
    placeholders.nodes.length === 0 && !workflow.disabled;

  const isRun = !!runSteps.start_from;

  const runStepsObj = runSteps.steps.reduce(
    (a, b) => {
      const exists = a[b.job_id];
      // to make sure that a pre-existing error state preempts the success.
      // this is for nodes that run multiple times
      // TODO: we might want to show a state for the multiple runs of the step later on.
      let step_value: RunStep;
      if (b.exit_reason === 'success' && exists?.exit_reason === 'fail')
        step_value = exists;
      else step_value = b;
      a[b.job_id] = { ...step_value };
      return a;
    },
    {} as Record<string, RunStep>
  );

  // Count duplicate steps for each job_id
  const duplicateCounts = runSteps.steps.reduce(
    (counts, step) => {
      counts[step.job_id] = (counts[step.job_id] || 0) + 1;
      return counts;
    },
    {} as Record<string, number>
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
        model.width = NODE_WIDTH;
        model.height = NODE_HEIGHT;

        model.data.allowPlaceholder = allowPlaceholder;
        model.data.isRun = isRun;
        model.data.runData = runStepsObj[node.id];
        model.data.duplicateRunCount = duplicateCounts[node.id] || 0;
        if (item.id === runSteps.start_from) {
          const startBy =
            type === 'trigger' ? 'Trigger' : runSteps.run_by || 'unknown';
          model.data.startInfo = {
            started_at: runSteps.inserted_at,
            startBy,
          };
        }

        if (type === 'trigger') {
          const triggerNode = node as Lightning.TriggerNode;
          model.data.trigger = {
            type: triggerNode.type,
            enabled: triggerNode.enabled,
            ...(triggerNode.type === 'cron' && {
              cron_expression: triggerNode.cron_expression,
            }),
            ...(triggerNode.type === 'webhook' && {
              has_auth_method: triggerNode.has_auth_method,
            }),
            ...(triggerNode.type === 'kafka' && {
              has_auth_method: triggerNode.has_auth_method,
            }),
          };
        }
        styleNode(model);
      } else {
        const edge = item as Lightning.Edge;
        const label = getEdgeLabel(edge);
        model.source = edge.source_trigger_id || edge.source_job_id;
        model.target = edge.target_job_id;
        model.type = 'step';
        model.label = label;
        model.markerEnd = {
          type: 'arrowclosed',
          width: 32,
          height: 32,
        };
        model.data = {
          condition_type: edge.condition_type,
          // TODO something is up here - ?? true is a hack
          // without it, new edges are marked as disabled
          errors: edge.errors,
          enabled: edge.enabled ?? true,
          label,
          isRun,
          didRun: !!(
            (runStepsObj[edge.source_job_id] ||
              edge.source_trigger_id === runSteps.start_from) &&
            runStepsObj[edge.target_job_id]
          ),
        };

        // Note: we don't allow the user to disable the edge that goes from a
        // trigger to a job, but we want to show it as if it were disabled when
        // the source trigger is disabled. This code does that.
        const source = nodes.find(x => x.id == model.source);
        if (source != null && source.type == 'trigger') {
          model.data.enabled = source?.data.enabled;
        }

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
      return styleNode(n);
    }),
  ] as Flow.Node[];

  const edges = [...placeholders.edges.map(e => styleEdge(e))] as Flow.Edge[];

  process(workflow.jobs, nodes, 'job');
  process(workflow.triggers, nodes, 'trigger');
  process(workflow.edges, edges, 'edge');

  const sortedEdges = edges.sort(sortOrderForSvg);

  return { nodes, edges: sortedEdges, disabled: workflow.disabled };
};

export default fromWorkflow;
