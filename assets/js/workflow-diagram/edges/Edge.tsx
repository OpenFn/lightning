import React, { FC } from 'react';
import {
  StepEdge,
  EdgeProps,
  getBezierPath,
  EdgeLabelRenderer,
} from 'reactflow';
import { labelStyles } from '../styles';

const CustomEdge: FC<EdgeProps> = props => {
  const {
    sourceX,
    sourceY,
    targetX,
    targetY,
    sourcePosition,
    targetPosition,
    selected,
  } = props;
  const { label, ...stepEdgeProps } = props;

  // TODO surely we can use a simpler calculation here?
  const [_path, labelX, labelY] = getBezierPath({
    sourceX,
    sourceY,
    sourcePosition,
    targetX,
    targetY,
    targetPosition,
  });

  return (
    <>
      <StepEdge {...stepEdgeProps} />
      <EdgeLabelRenderer>
        <div
          style={{
            position: 'absolute',
            transform: `translate(-50%, -50%) translate(${labelX}px,${labelY}px)`,
            background: 'white',
            pointerEvents: 'all',
            ...labelStyles(selected),
          }}
          className="nodrag nopan"
        >
          {label}
        </div>
      </EdgeLabelRenderer>
    </>
  );
};

export default CustomEdge;
