import React, { FC } from 'react';
import {
  StepEdge,
  EdgeProps,
  getBezierPath,
  EdgeLabelRenderer,
} from 'reactflow';

// TODO should these be driven by tailwind?
// These are copies of the react-flow defaults, changing
// them here won't change the edge colour (but it should!)
const EDGE_COLOR = '#b1b1b7';
const EDGE_COLOR_SELECTED = '#555555';

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

  const primaryColor = selected ? EDGE_COLOR_SELECTED : EDGE_COLOR;

  return (
    <>
      <StepEdge {...stepEdgeProps} />
      <EdgeLabelRenderer>
        <div
          style={{
            position: 'absolute',
            transform: `translate(-50%, -50%) translate(${labelX}px,${labelY}px)`,
            background: 'white',
            width: '32px',
            height: '32px',
            border: `solid 2px ${primaryColor}`,
            borderRadius: 16,
            fontSize: 18,
            textAlign: 'center',
            fontWeight: 700,
            color: primaryColor,
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
