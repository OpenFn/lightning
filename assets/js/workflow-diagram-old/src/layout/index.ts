/**
 * Layout algorithm code for automatically providing dimensions and positions
 * for Jobs, Triggers and Operations.
 *
 * It works by first converting a `ProjectSpace` into a nested `ElkNode`-like
 * object (with `__flowProps__` added for later).
 * Then the resulting object is passed to ELKs layout function, which adds
 * coordinates to all the nodes.
 * And finally with `flattenElk` we both flatten and convert the ELK object
 * to one compatible with React Flow.
 */

import type { LayoutOptions } from 'elkjs';
import ELK from 'elkjs/lib/elk.bundled.js';

import { FlowJob, FlowTrigger, Job, ProjectSpace, Workflow } from 'types';
import {
  jobNodeFactory,
  operationEdgeFactory,
  operationNodeFactory,
  triggerNodeFactory,
  workflowNodeFactory,
} from './factories';
import { toFlowEdge, toFlowNode } from './flow-nodes';
import { ElkNodeEdges, FlowElkEdge, FlowElkNode, FlowNodeEdges } from './types';

function deriveOperations(job: Job): ElkNodeEdges {
  if (job.operations) {
    return job.operations.reduce<ElkNodeEdges>(
      ([nodes, edges], operation) => {
        const prevOperation = nodes[nodes.length - 1];

        const edge: FlowElkEdge[] = prevOperation
          ? [operationEdgeFactory(operation, prevOperation)]
          : [];

        return mergeTuples(
          [nodes, edges],
          [[operationNodeFactory(operation)], edge]
        );
      },
      [[], []]
    );
  }

  return [[], []];
}

function deriveCron(job: Job, workflow: Workflow): ElkNodeEdges {
  const [operationNodes, operationEdges] = deriveOperations(job);

  const triggerNode: FlowElkNode = triggerNodeFactory(job, workflow);

  const jobNode: FlowElkNode = {
    ...jobNodeFactory(job),
    children: operationNodes,
    edges: operationEdges,
  };

  const triggerJobEdge: FlowElkEdge = {
    id: `${triggerNode.id}->${job.id}`,
    sources: [triggerNode.id],
    targets: [jobNode.id],
    labels: [{ text: 'on match' }],
    __flowProps__: { animated: false },
  };

  return mergeTuples([[triggerNode, jobNode], [triggerJobEdge]], [[], []]);
}

function deriveWebhook(job: Job, workflow: Workflow): ElkNodeEdges {
  const [operationNodes, operationEdges] = deriveOperations(job);

  const triggerNode = triggerNodeFactory(job, workflow);

  const jobNode = {
    ...jobNodeFactory(job),
    children: operationNodes,
    edges: operationEdges,
  };

  const edge: FlowElkEdge = {
    id: `${triggerNode.id}->${job.id}`,
    sources: [triggerNode.id],
    targets: [jobNode.id],
    labels: [{ text: 'on receipt' }],
    __flowProps__: { animated: false },
  };

  return mergeTuples([[triggerNode, jobNode], [edge]], [[], []]);
}

function deriveFlow(job: FlowJob): ElkNodeEdges {
  const [operationNodes, operationEdges] = deriveOperations(job);

  const jobNode: FlowElkNode = {
    ...jobNodeFactory(job),
    children: operationNodes,
    edges: operationEdges,
  };

  const label =
    job.trigger.type == 'on_job_failure' ? 'on failure' : 'on success';

  const edge: FlowElkEdge = {
    id: `${job.trigger.upstreamJob}->${job.id}`,
    sources: [job.trigger.upstreamJob],
    targets: [jobNode.id],
    __flowProps__: { animated: false },
    labels: [{ text: label }],
  };

  return mergeTuples([[jobNode], [edge]], [[], []]);
}

export function deriveNodesWithEdges(
  job: Job,
  workflow: Workflow
): ElkNodeEdges {
  switch (job.trigger.type) {
    case 'cron':
      return deriveCron(job, workflow);

    case 'webhook':
      return deriveWebhook(job, workflow);

    case 'on_job_failure':
    case 'on_job_success':
      return deriveFlow(job as FlowJob);
    default:
      throw new Error(`Got unrecognised job: ${JSON.stringify(job)}`);
  }
}

function mergeTuples(
  [a, c]: [any[], any[]],
  [b, d]: [any[], any[]]
): [any[], any[]] {
  return [
    [...a, ...b],
    [...c, ...d],
  ];
}

function hasDescendent(projectSpace: ProjectSpace, job: Job): boolean {
  return Boolean(
    projectSpace.jobs.find(j => {
      if (j.trigger.type in ['on_job_failure', 'on_job_success']) {
        return (j.trigger as FlowTrigger).upstreamJob == job.id;
      }
    })
  );
}

const rootLayoutOptions: LayoutOptions = {
  'elk.algorithm': 'elk.box',
  'elk.box.packingMode': 'GROUP_DEC',
  // "elk.separateConnectedComponents": "true",
  // "elk.hierarchyHandling": "INCLUDE_CHILDREN",
  'elk.alignment': 'TOP',
  // "elk.expandNodes": "true",
  'spacing.nodeNode': '40',
  'spacing.nodeNodeBetweenLayers': '45',
  'spacing.edgeNode': '25',
  'spacing.edgeNodeBetweenLayers': '20',
  'spacing.edgeEdge': '20',
  'spacing.edgeEdgeBetweenLayers': '15',
};

function groupByWorkflow(projectSpace: ProjectSpace): Map<Workflow, Job[]> {
  return new Map(
    projectSpace.workflows.map(workflow => [
      workflow,
      projectSpace.jobs.filter(({ workflowId }) => workflowId == workflow.id),
    ])
  );
}

/**
 * Turns a ProjectSpace object into a FlowElkNode, this can be handled to ELK
 * for layout calculation.
 *
 * The extended interface (`FlowElkNode`) has extra properties on it in order
 * to preserve specific information for React Flow.
 *
 * @param projectSpace
 */
export function toElkNode(projectSpace: ProjectSpace): FlowElkNode {
  let nodeEdges: ElkNodeEdges = [[], []];

  for (const [workflow, jobs] of groupByWorkflow(projectSpace)) {
    let [jobNodes, jobEdges] = jobs.reduce<ElkNodeEdges>(
      (nodesAndEdges, job) => {
        return mergeTuples(
          nodesAndEdges,
          deriveNodesWithEdges(
            {
              ...job,
              hasDescendents: hasDescendent(projectSpace, job),
            },
            workflow
          )
        );
      },
      [[], []]
    );

    nodeEdges = mergeTuples(nodeEdges, [
      [
        {
          ...workflowNodeFactory(workflow),
          children: jobNodes,
          edges: jobEdges,
        },
      ],
      [],
    ]);
  }

  const [children, edges] = nodeEdges;

  // This root node gets ignored later, but we need a starting point for
  // gathering up all workflows as children
  return {
    id: 'root',
    layoutOptions: rootLayoutOptions,
    children,
    edges,
    __flowProps__: { data: { label: '' }, type: 'root' },
  };
}

const elk = new ELK();

export function doLayout(node: FlowElkNode) {
  return elk.layout(node) as Promise<FlowElkNode>;
}

export function toFlow(node: FlowElkNode): FlowNodeEdges {
  // Skip the 'root' graph node, head straight for the children, they are
  // the workflows.
  const flow = (node!.children || []).reduce<FlowNodeEdges>(
    (acc, child) => mergeTuples(acc, flattenElk(child)),
    [[], []]
  );

  return flow;
}

/**
 * Flattens an ELK node into a tuple of Nodes and Edges that are
 * compatible with React Flow.
 */
export function flattenElk(
  node: FlowElkNode,
  parent?: FlowElkNode
): FlowNodeEdges {
  return (node.children || []).reduce<FlowNodeEdges>(
    (acc: FlowNodeEdges, child) => {
      const [childNodes, childEdges] = flattenElk(child, node);

      return mergeTuples(acc, [[...childNodes], childEdges]);
    },
    [
      [toFlowNode(node, parent)],
      (node.edges || []).map(toFlowEdge),
    ] as FlowNodeEdges
  );
}
