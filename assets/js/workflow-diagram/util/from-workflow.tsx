import React from 'react';
import { Lightning, Flow, Positions } from '../types';
import { sortOrderForSvg, styleEdge, styleNode, iconStyles } from '../styles';

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

  if (condition_label) {
    const l =
      condition_label.length > 16
        ? condition_label.slice(0, 16) + '...'
        : condition_label;
    label = (
      <>
        <span style={iconStyles}>{label}</span>
        <span
          style={{
            lineHeight: iconStyles.lineHeight,
            verticalAlign: iconStyles.verticalAlign,
          }}
        >
          {l}
        </span>
      </>
    );
  }

  return label;
}

const fromWorkflow = (
  workflow: Lightning.Workflow,
  positions: Positions,
  placeholders: Flow.Model = { nodes: [], edges: [] },
  selectedId: string | null
): Flow.Model => {
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

        model.data.allowPlaceholder = allowPlaceholder;

        if (type === 'trigger') {
          model.data.trigger = {
            type: (node as Lightning.TriggerNode).type,
            enabled: (node as Lightning.TriggerNode).enabled,
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
          enabled: edge.enabled ?? true,
          label,
        };

        // Note: we don't allow the user to disable the edge that goes from a
        // trigger to a job, but we want to show it as if it were disabled when
        // the source trigger is disabled. This code does that.
        const source = nodes.find(x => x.id == model.source);
        if (source.type == 'trigger') {
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

  return { nodes, edges: sortedEdges };
};

export default fromWorkflow;
