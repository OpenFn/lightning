import test from 'ava';

// TODO - Is any of this testing still required?
// import { ProjectSpace } from '../js/workflow-diagram-old/src/types';
// import {
//   toElkNode,
//   toFlow,
//   doLayout,
// } from '../js/workflow-diagram-old/src/layout/index';
// import {
//   FlowElkNode,
//   FlowNodeEdges,
// } from '../js/workflow-diagram-old/src/layout/types';
import { getFixture } from './helpers';

test.skip('toElkNode should convert a project space to a workflow', async t => {
  // const projectSpace = await getFixture<ProjectSpace>(
  //   'single-workflow-projectspace'
  // );

  // const expected = await getFixture<FlowElkNode>('single-workflow-elknode');
  // const elkNode = toElkNode(projectSpace);
  // for (let i = 0; i < expected.children!.length; i++) {
  //   const child = expected.children![i];
  //   const actual = elkNode.children![i];

  //   t.deepEqual(
  //     actual.layoutOptions,
  //     child.layoutOptions,
  //     `Child#${i} didn't match the expected layoutOptions`
  //   );

  //   t.deepEqual(actual, child, `Child#${i} didn't match the expected one`);
  // }

  // t.deepEqual(elkNode.layoutOptions, expected.layoutOptions);
  // t.deepEqual(elkNode.__flowProps__, expected.__flowProps__);
});

test.skip('toFlow should convert a FlowElkNode to FlowNodeEdges with layout', async t => {
  // const flowElkNode = await getFixture<FlowElkNode>('single-workflow-elknode');
  // const [expectedNodes, expectedEdges] = await getFixture<FlowNodeEdges>(
  //   'single-workflow-nodeedges'
  // );

  // const [nodes, edges] = toFlow(await doLayout(flowElkNode));

  // for (let i = 0; i < expectedNodes.length; i++) {
  //   const node = expectedNodes[i];
  //   t.deepEqual(nodes[i], node, `Node#${i} didn't match the expected one`);
  // }

  // for (let i = 0; i < expectedEdges.length; i++) {
  //   const edge = expectedEdges[i];
  //   t.deepEqual(edges[i], edge, `Edge#${i} didn't match the expected one`);
  // }
});
