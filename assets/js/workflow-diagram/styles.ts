/**
 * This file contains cosmetic (not structural) style information
 * for nodes and edges in the diagram
 *
 * This is supposed to make changing simple styles easier. Nore sure
 * if it's going to help yet
 */

// TODO should these be driven by tailwind?
// These are copies of the react-flow defaults, changing
// them here won't change the edge colour (but it should!)
export const EDGE_COLOR = '#b1b1b7';
export const EDGE_COLOR_SELECTED = '#555555';

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

export const nodeIconStyles = (selected?: boolean) => {
  const size = 100;
  const primaryColor = selected ? EDGE_COLOR_SELECTED : EDGE_COLOR;
  return {
    width: size,
    height: size,
    anchorx: size / 2,
    strokeWidth: 2,
    style: {
      stroke: primaryColor,
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
