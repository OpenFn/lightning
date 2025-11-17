import { BezierEdge } from '@xyflow/react';

import { EDGE_COLOR_SELECTED } from '../styles';

export default (props: {
  fromX: number;
  fromY: number;
  toX: number;
  toY: number;
}) => {
  const { fromX, fromY, toX, toY } = props;
  return (
    <BezierEdge
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
