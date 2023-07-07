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

const Shape = ({ shape, width, height, strokeWidth, styles }) => {
  if (shape === 'circle') {
    return <Circle width={width} height={height} styles={styles} strokeWidth={strokeWidth}/>
  } else {
    return <Rect width={width} height={height} styles={styles} strokeWidth={strokeWidth} />
  }
}

const Label = ({ children }) => {
  if (children && children.length) {
    return (<p className="line-clamp-2 align-left text-m">
      {children}
    </p>)
  }
  return null;
}
const SubLabel = ({ children }) => {
  if (children && children.length) {
    return (<p className="line-clamp-2 align-left text-sm text-slate-500">
      {children}
    </p>)
  }
  return null;
}

const Node = ({
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

  // New stuff we need to support
  icon, // displayed inside the SVG shape
  status, // [ok | error | warning, message]. Passed into a status widget

  // title and subtitle?
  // name and adaptor?
  // I think I prefer this to be generic
  label, // main label which appears to the right
  sublabel, // A smaller label to the right

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
  // TODO I don't really think we're controlling the node size properly
  // what will very long labels do?
  return (
    <div className="flex flex-row">
      <div>
        {targetPosition && <Handle
          type="target"
          isConnectable={isConnectable}
          position={targetPosition}
          style={{ visibility: 'hidden', height: 0, top: 0, left: (strokeWidth + anchorx) }}
        />}
        <svg style={{ maxWidth: '110px', maxHeight: '110px' }}>
          <Shape shape={shape} width={width} height={height} strokeWidth={strokeWidth} styles={style}/>
        </svg>
        {sourcePosition && <Handle
          type="source"
          isConnectable={isConnectable}
          position={sourcePosition}
          style={{ visibility: 'hidden', height: 0, top: height, left: (strokeWidth + anchorx) }}/>}
      </div>
      <div className="flex flex-col flex-1 justify-center ml-2">
          <Label>{label}</Label>
          <SubLabel>{sublabel}</SubLabel>
      </div>
    </div>
  )
};

Node.displayName = 'JobNode';

export default memo(Node);
