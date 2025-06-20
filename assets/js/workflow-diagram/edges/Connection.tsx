import { BezierEdge, type Handle } from '@xyflow/react';
import { EDGE_COLOR, EDGE_COLOR_SELECTED } from '../styles';

export default (props: {
  fromX: number;
  fromY: number;
  toX: number;
  toY: number;
  fromHandle?: Handle;
}) => {
  const { fromX, fromY, toX, toY, fromHandle } = props;
  const isNodeCreator = fromHandle?.id === "node-creator";
  return (
    <BezierEdge
      sourceX={fromX}
      sourceY={fromY}
      targetX={toX}
      targetY={toY}
      animated={true}
      zIndex={-1}
      style={{
        stroke: isNodeCreator ? EDGE_COLOR : EDGE_COLOR_SELECTED,
        strokeWidth: isNodeCreator ? 2 : 4,
        ...(isNodeCreator ? {} : { strokeDasharray: '4, 4' }),
        opacity: 0.7,
      }}
    />
  );
};
