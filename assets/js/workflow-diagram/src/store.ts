import {
  applyEdgeChanges,
  applyNodeChanges,
  Edge,
  EdgeChange,
  Node,
  NodeChange,
  OnEdgesChange,
  OnNodesChange,
} from 'react-flow-renderer';
import { ProjectSpace, Workflow } from './types';
import create from 'zustand';
import { doLayout, toElkNode, toFlow } from './layout';
import { FlowElkNode } from './layout/types';
import { workflowNodeFactory } from './layout/factories';

type RFState = {
  nodes: Node[];
  edges: Edge[];
  elkNode: FlowElkNode | null;
  projectSpace: ProjectSpace | null;
  onNodesChange: OnNodesChange;
  onEdgesChange: OnEdgesChange;
};

export const useStore = create<RFState>((set, get) => ({
  projectSpace: null,
  elkNode: null,
  nodes: [],
  edges: [],
  onNodesChange: (changes: NodeChange[]) => {
    set({
      nodes: applyNodeChanges(changes, get().nodes),
    });
  },
  onEdgesChange: (changes: EdgeChange[]) => {
    set({
      edges: applyEdgeChanges(changes, get().edges),
    });
  },
}));

export async function setProjectSpace(
  projectSpace: ProjectSpace
): Promise<void> {
  let elkNode: FlowElkNode = toElkNode(projectSpace);

  elkNode = await doLayout(elkNode);

  const [nodes, edges] = toFlow(elkNode);

  useStore.setState({ nodes, edges, projectSpace, elkNode });
}

export async function addWorkspace(workflow: Workflow) {
  let elkNode = useStore.getState().elkNode;

  if (elkNode) {
    (elkNode.children || []).push(workflowNodeFactory(workflow));
  } else {
    throw new Error("ElkNode layout not present, can't addWorkspace.");
  }

  elkNode = await doLayout(elkNode);

  const [nodes, edges] = toFlow(elkNode);

  useStore.setState({ nodes, edges, elkNode });
}
