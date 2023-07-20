import React, { FC } from 'react';
import { StepEdge, EdgeProps, EdgeLabelRenderer } from 'reactflow';
import { labelStyles } from '../styles';

const CustomEdge: FC<EdgeProps> = props => {
  const { sourceX, sourceY, targetX, targetY, selected } = props;
  const { label, ...stepEdgeProps } = props;

  // Simply label position calculation
  // If this breaks down, use getBezierPath from https://reactflow.dev/docs/examples/edges/custom-edge/
  const labelX = (sourceX + targetX) / 2;
  const labelY = (sourceY + targetY) / 2;
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
