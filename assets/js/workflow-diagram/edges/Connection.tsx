import React from 'react';
import { EDGE_COLOR_SELECTED } from '../styles';
import { BezierEdge } from 'reactflow';

export default props => {
  const { fromX, fromY, toX, toY } = props;
  return (
    <BezierEdge
      id="tmp"
      sourceX={fromX}
      sourceY={fromY}
      targetX={toX}
      targetY={toY}
      animated={true}
      zIndex={-1}
      style={{
        stroke: EDGE_COLOR_SELECTED,
        strokeWidth: 4,
        strokeDasharray: '4, 4',
        opacity: 0.7,
      }}
    />
  );
};
