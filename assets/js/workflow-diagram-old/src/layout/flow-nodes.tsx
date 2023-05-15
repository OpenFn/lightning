/**
 * A collection of functions used to convert ELK Node objects into
 * React Flow Nodes.
 */
import { Edge, Node } from "reactflow";
import { FlowElkEdge, FlowElkNode } from "./types";
import cc from "classcat";
import { ElkLabel } from "elkjs";

/**
 * Builds a Node object ready to be given to React Flow.
 * @param node a node that has been passed through Elk with it's layout
 * calculations applied
 */
export function toFlowNode(node: FlowElkNode, parent?: FlowElkNode): Node {
  const isContainer = hasChildren(node);

  return {
    id: node.id,
    style: {
      height: node.height,
      width: node.width,
      zIndex: isContainer ? -1 : 1,
    },
    selectable: node.__flowProps__.selectable ? true : false,
    position: { x: node.x || 0, y: node.y || 0 },
    ...nodeData(node),
    ...nodeType(node),
    ...childAttrs(parent),
  };
}

function childAttrs(parent: FlowElkNode | undefined): Partial<Node> {
  if (parent) {
    return {
      parentNode: parent.id,
      extent: "parent",
    };
  }

  return {};
}

function firstLabel(edge: FlowElkEdge): null | string {
  const first: ElkLabel = (edge.labels || [])[0];
  if (first) {
    return first.text || null;
  }

  return null;
}

/**
 * Builds an Edge object ready to be given to React Flow.
 * @param edge an edge that has been passed through Elk with it's layout
 * calculations applied
 */
export function toFlowEdge(edge: FlowElkEdge): Edge {
  const className = cc({
    "dashed-edge": edge.__flowProps__.dashed,
    "dotted-edge": edge.__flowProps__.dotted,
  });
  const { markerEnd } = edge.__flowProps__;

  return {
    id: edge.id,
    label: firstLabel(edge),
    source: edge.sources[0],
    target: edge.targets[0],
    animated: edge.__flowProps__.animated,
    labelBgStyle: { fill: "#f3f4f6" },
    className,
    ...(markerEnd ? { markerEnd } : {}),
  };
}

function nodeData(node: FlowElkNode) {
  if (node.__flowProps__?.data) {
    return {
      data: {
        hasChildren: hasChildren(node),
        ...node.__flowProps__.data,
      },
    };
  }

  return { data: {} };
}

function nodeType(node: FlowElkNode) {
  if (node.__flowProps__.type) {
    {
      return { type: node.__flowProps__.type };
    }
  }

  return {};
}

function hasChildren(node: FlowElkNode): Boolean {
  if (node.children && node.children.length > 0) {
    return true;
  }

  return false;
}
