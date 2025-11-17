import { BezierEdge, type EdgeProps, EdgeLabelRenderer } from '@xyflow/react';

import { edgeLabelStyles } from '../styles';

const CustomEdge: React.FC<EdgeProps<{ enabled?: boolean }>> = props => {
  const { sourceX, sourceY, targetX, targetY, selected, data } = props;
  const { label, ...stepEdgeProps } = props;

  // Simply label position calculation
  // If this breaks down, use getBezierPath from https://reactflow.dev/docs/examples/edges/custom-edge/
  const labelX = (sourceX + targetX) / 2;
  const labelY = (sourceY + targetY) / 2;
  return (
    <>
      {/* Curvature does nothing?? */}
      <BezierEdge {...stepEdgeProps} pathOptions={{ curvature: 0.4 }} />
      {label && (
        <EdgeLabelRenderer>
          <div
            style={{
              position: 'absolute',
              transform: `translate(-50%, -50%) translate(${labelX}px,${labelY}px)`,
              background: 'white',
              pointerEvents: 'all',
              ...edgeLabelStyles(selected, data?.neighbour, stepEdgeProps.data),
            }}
            className="nodrag nopan cursor-pointer"
          >
            {label}
          </div>
        </EdgeLabelRenderer>
      )}
    </>
  );
};

export default CustomEdge;
