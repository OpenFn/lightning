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
export const EDGE_COLOR_DISABLED = '#E1E1E1';
export const EDGE_COLOR_SELECTED = '#4f46e5';
export const EDGE_COLOR_SELECTED_DISABLED = '#bdbaf3';

export const ERROR_COLOR = '#ef4444';

const iconColorMap = {
  on_job_success: '#e7f3e8',
  on_job_failure: '#ffe9e9',
  always: '#ffffef',
  js_expression: '#eff3ff',
};

export const edgeLabelIconStyles = (type: string) => ({
  fontSize: 24,
  // marginRight: '6px',
  fontWeight: 700,
  // display: 'inline-block',
  display: 'flex',
  height: '46px',
  width: '46px',
  // lineHeight: '30px',
  // verticalAlign: 'middle',
  borderStyle: 'solid',
  borderWidth: '2px',
  borderRadius: '100%',
  borderColor: 'inherit',
  backgroundColor: 'white', // iconColorMap[type],

  alignItems: 'center',
  justifyContent: 'center',

  // cheat (good for {} though)
  // paddingBottom: '2px',

  // zIndex: 1,
});

export const edgeLabelTextStyles = {
  borderStyle: 'solid',
  borderWidth: '2px',
  borderTopRightRadius: '8px',
  borderBottomRightRadius: '8px',
  borderColor: 'inherit',
  backgroundColor: 'white',
  padding: '2px 6px',
  paddingLeft: '8px',
  marginLeft: '-11px',
  height: '34px',
  borderLeft: 'solid 2px white',
};

export const edgeLabelStyles = (selected?: boolean, data) => {
  const { label, enabled } = data;
  const primaryColor = (selected?: boolean, enabled?: boolean) => {
    if (enabled) return selected ? EDGE_COLOR_SELECTED : EDGE_COLOR;
    return selected ? EDGE_COLOR_SELECTED_DISABLED : EDGE_COLOR_DISABLED;
  };

  // this is just styling the parent of the edge label
  // the icon and label will inherit

  // const backgroundColor = enabled ? 'white' : '#F6F6F6';
  return {
    borderColor: primaryColor(selected, enabled),
    // set the text colour deliberately a bit darker to get the right contrast
    color: '#a9a8a8', //primaryColor(selected, enabled),
    backgroundColor: 'transparent',
    display: 'flex',
    alignItems: 'center',
    opacity: enabled ? 1 : 0.9,
  };
  // if (typeof label === 'string') {
  //   return {
  //     width: '32px',
  //     height: '32px',
  //     border: `solid 2px ${primaryColor(selected, enabled)}`,
  //     borderRadius: 16,
  //     fontSize: 18,
  //     textAlign: 'center' as const,
  //     verticalAlign: 'middle',
  //     fontWeight: 700,
  //     color: primaryColor(selected, enabled),
  //     backgroundColor,
  //   };
  // } else {
  //   return {
  //     ...edgeLabelIconStyles,
  //     padding: '0 4px',
  //     border: `solid 2px ${primaryColor(selected, enabled)}`,
  //     borderRadius: 8,
  //     display: 'flex',
  //     alignItems: 'center',
  //     fontSize: 14,
  //     textAlign: 'center' as const,
  //     fontWeight: 500,
  //     color: primaryColor(selected, enabled),
  //     backgroundColor,
  //   };
  // }
};

export const styleItem = (item: Flow.Edge | Flow.Node) => {
  let edge = item as Flow.Edge;
  if (edge.target && edge.source) {
    return styleEdge(edge);
  }
  return styleNode(item as Flow.Node);
};

export const styleNode = (node: Flow.Node) => {
  const { data } = node;

  if (data?.enabled == false) {
    node.style = {
      opacity: 0.5,
    };
  }

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

  if (!edge.data?.enabled) {
    edge.style.strokeDasharray = '4, 4';
    edge.style.strokeWidth = '1.5px';
    edge.style.opacity = 0.5;
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

export const sortOrderForSvg = (a: object, b: object) => {
  if (a.data.enabled > b.data.enabled) {
    return 1;
  }

  if (a.data.enabled < b.data.enabled) {
    return -1;
  }

  return a.selected - b.selected;
};
