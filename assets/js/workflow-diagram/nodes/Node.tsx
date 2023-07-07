import React, { memo } from 'react';
import { Handle, NodeProps } from 'reactflow';
import { NODE_HEIGHT, NODE_WIDTH } from '../constants';

type NodeData = any;

const Circle = ({ width, height, styles, strokeWidth }) =>
  <ellipse
  // Note we have to offset the x/y position by the stroke width or the stroke will clip outside the canvas
    cx={strokeWidth + (width / 2)}
    cy={strokeWidth + (height / 2)}
    rx={width / 2}
    ry={height / 2}
    strokeWidth={strokeWidth}
    {...styles}
  />

const Rect = ({ width, height, styles, strokeWidth }) => 
  <rect
    // Note we have to offset the x/y position by the stroke width or the stroke will clip outside the canvas
    x={strokeWidth}
    y={strokeWidth}
    rx={16}
    width={width}
    height={height}
    strokeWidth={strokeWidth}
    {...styles}
  />;

const Node = ({
  label,
  sublabel,
  labelClass = '',
  tooltip,
  interactive = true,
  data,
  shape,
  isConnectable,
  selected,
  targetPosition,
  sourcePosition,
  toolbar,
}: NodeProps<NodeData>) => {

  // Values to control the svg shape
  // TODO are these values constant?
  const width = 100;
  const height = 100;
  const anchorx = width / 2;
  const strokeWidth = 2;
  const style = {
    stroke: '#c0c0c0',
    fill: 'white'
  }
  return (
    <div className="flex flex-row" style={{ maxWidth: '300px' }}>
      <div>
        {targetPosition && <Handle
          type="target"
          isConnectable={isConnectable}
          position={targetPosition}
          style={{ visibility: 'hidden', height: 0, top: 0, left: (strokeWidth + anchorx) }}
        />}
        <svg style={{ maxWidth: '110px', maxHeight: '110px' }}>
          {shape === 'circle' && <Circle width={width} height={height} styles={style} strokeWidth={strokeWidth}/>}
          {shape != 'circle' && <Rect width={width} height={height} styles={style} strokeWidth={strokeWidth} />}
        </svg>
        {sourcePosition && <Handle
          type="source"
          isConnectable={isConnectable}
          position={sourcePosition}
          style={{ visibility: 'hidden', height: 0, top: height, left: (strokeWidth + anchorx) }}/>}
      </div>
      <div className="flex-1 justify-left" style={{ maxWidth: '150px' }}>
        {label && <p className={`line-clamp-2 align-left${labelClass}`}>{label}</p> }
        {sublabel && <p className={`line-clamp-2 align-left${labelClass}`}>{sublabel}</p>         }
      </div>
    </div>
  )
};

Node.displayName = 'JobNode';

export default memo(Node);
