import React from 'react';
import { EDGE_COLOR_SELECTED } from '../styles';

// TODO this is taken from https://reactflow.dev/examples/edges/custom-connectionline
// but surely we can just use a normal edge?
export default props => {
  const { fromX, fromY, toX, toY } = props;

  return (
    <g>
      <path
        fill="none"
        stroke={EDGE_COLOR_SELECTED}
        strokeWidth={3}
        strokeDasharray={'4, 4'}
        opacity={0.7}
        className="animated"
        d={`M${fromX},${fromY} C ${fromX} ${toY} ${fromX} ${toY} ${toX},${toY}`}
      />
      <circle
        cx={toX}
        cy={toY}
        fill="#fff"
        r={3}
        stroke={EDGE_COLOR_SELECTED}
        strokeWidth={3}
        strokeDasharray={'4, 4'}
        opacity={0.7}
      />
    </g>
  );
};

// export default props => {
//   return <SmoothStepEdge
//       fromX=P
//     />;
// };
