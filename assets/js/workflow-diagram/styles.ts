/**
 * This file contains cosmetic (not structural) style information
 * for nodes and edges in the diagram
 *
 * This is supposed to make changing simple styles easier. Nore sure
 * if it's going to help yet
 */
import { Flow } from './types';
// import { isPlaceholder } from './util/placeholder';

export const EDGE_COLOR = '#b1b1b7';
export const EDGE_COLOR_SELECTED = '#4f46e5';

export const ERROR_COLOR = '#ef4444';

export const labelStyles = (selected?: boolean) => {
  const primaryColor = selected ? EDGE_COLOR_SELECTED : EDGE_COLOR;
  return {
    width: '32px',
    height: '32px',
    border: `solid 2px ${primaryColor}`,
    borderRadius: 16,
    fontSize: 18,
    textAlign: 'center' as const,
    fontWeight: 700,
    color: primaryColor,
  };
};

export const styleItem = (item: Flow.Edge | Flow.Node) => {
  let edge = item as Flow.Edge;
  if (edge.target && edge.source) {
    return styleEdge(edge);
  }
  return styleNode(item as Flow.Node);
};

export const styleNode = (node: Flow.Node) => {
  return node;
};

export const styleEdge = (edge: Flow.Edge) => {
  edge.style = {
    strokeWidth: '2',
    stroke: edge.selected ? EDGE_COLOR_SELECTED : EDGE_COLOR,
  };

  if (edge.data?.placeholder) {
    edge.style.strokeDasharray = '4, 4';
    edge.style.strokeWidth = '1.5px';
  }

  if (edge.markerEnd) {
    edge.markerEnd = {
      ...edge.markerEnd,
      width: 15,
      color: edge.selected ? EDGE_COLOR_SELECTED : EDGE_COLOR,
    };
  }
  return edge;
};

export const nodeIconStyles = (selected?: boolean, hasErrors?: boolean) => {
  const size = 100;
  const primaryColor = selected ? EDGE_COLOR_SELECTED : EDGE_COLOR;
  return {
    width: size,
    height: size,
    anchorx: size / 2,
    strokeWidth: 2,
    style: {
      stroke: hasErrors ? ERROR_COLOR : primaryColor,
      fill: 'white',
    },
  };
};

export const nodeLabelStyles = (selected: boolean) => {
  const primaryColor = selected ? EDGE_COLOR_SELECTED : EDGE_COLOR;
  return {
    color: primaryColor,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  };
};
