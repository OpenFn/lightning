import {
  applyEdgeChanges,
  applyNodeChanges,
  Edge,
  EdgeChange,
  Node,
  NodeChange,
  NodeSelectionChange,
  OnEdgesChange,
  OnNodesChange,
  OnSelectionChangeFunc,
  ReactFlowInstance,
} from 'reactflow';
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
  onSelectedNodeChange: OnSelectionChangeFunc;
  reactFlowInstance: ReactFlowInstance | null;
  selectedNode: string | undefined;
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
  onSelectedNodeChange: (_data: { nodes: Node[] }) => {},
  reactFlowInstance: null,
  selectedNode: undefined,
}));

function markSelected(nodes: Node[], selectedNode: string | undefined) {
  if (!selectedNode) {
    return nodes;
  }

  return nodes.map(node => {
    if (selectedNode == node.id) {
      return {
        ...node,
        selected: true,
      };
    }

    return node;
  });
}

export async function setProjectSpace(
  projectSpace: ProjectSpace | string
): Promise<void> {
  if (typeof projectSpace == 'string') {
    projectSpace = JSON.parse(atob(projectSpace)) as ProjectSpace;
  }
  let elkNode: FlowElkNode = toElkNode(projectSpace);

  elkNode = await doLayout(elkNode);

  const [nodes, edges] = toFlow(elkNode);

  useStore.setState({
    nodes: markSelected(nodes, useStore.getState().selectedNode),
    edges,
    projectSpace,
    elkNode,
  });
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

export function setReactFlowInstance(rf: ReactFlowInstance) {
  useStore.setState({ reactFlowInstance: rf });
}

function debounce(fun: () => void, t: number | undefined) {
  let timeout: string | number | NodeJS.Timeout | undefined;
  return () => {
    clearTimeout(timeout);
    timeout = setTimeout(fun, t);
  };
}

export const fitView = debounce(() => {
  let reactFlowInstance = useStore.getState().reactFlowInstance;

  if (reactFlowInstance) {
    reactFlowInstance.fitView({ duration: 250 });
  }
}, 250);

export function unselectAllNodes() {
  const nodes = useStore.getState().nodes;
  const changes: NodeSelectionChange[] = nodes.map(({ id }) => ({
    id,
    type: 'select',
    selected: false,
  }));

  useStore.setState({ nodes: applyNodeChanges(changes, nodes) });
}

export function selectNode(selectedId: string) {
  const nodes = useStore.getState().nodes;
  const changes: NodeSelectionChange[] = nodes.map(node => {
    return {
      id: node.id,
      type: 'select',
      selected: selectedId == node.id,
    };
  });

  useStore.setState({
    nodes: applyNodeChanges(changes, nodes),
    selectedNode: selectedId,
  });
}
