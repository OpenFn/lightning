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

  allowSource = false,
  toolbar,
}: NodeProps<NodeData>) => {
  
  /// new node layout is gonna be shape plus content
  // difficulty: laying out to the shape, not the content

  const width = 100;
  const height = 100;
  const anchorx = width / 2;
  const strokeWidth = 2;
  const style = {
    stroke: '#c0c0c0',
    fill: 'transparent'
  }
  return (
    <div className="flex flex-row" style={{ maxWidth: '300px' }}>
      <div>
        {targetPosition && <Handle
          type="target"
          isConnectable={isConnectable}
          style={{ background:'red', visibility: 'visible', border: 'none', height: 0, top: 0, left: (strokeWidth + anchorx) }}
        />}
        <svg style={{ maxWidth: '110px', maxHeight: '110px' }}>
          {shape === 'circle' && <Circle width={width} height={height} styles={style} strokeWidth={strokeWidth}/>}
          {shape != 'circle' && <Rect width={width} height={height} styles={style} strokeWidth={strokeWidth} />}
        </svg>
        {sourcePosition && <Handle
          type="source"
          isConnectable={isConnectable}
          style={{ visibility: 'visible', border: 'none', height: 0, top: height, left: (strokeWidth + anchorx) }}/>}
      </div>
      <div className="flex-1 justify-left" style={{ maxWidth: '150px' }}>
        {label && <p className={`line-clamp-2 align-left${labelClass}`}>{label}</p> }
        {sublabel && <p className={`line-clamp-2 align-left${labelClass}`}>{sublabel}</p>         }
      </div>
    </div>
  )


  return (
    <div
      className={[
        'group',
        'bg-white',
        interactive ? 'cursor-pointer' : 'cursor-default',
        'h-full',
        'p-1',
        'rounded-md',
        'shadow-sm',
        'text-center',
        'text-xs',
        selected ? 'ring-2' : 'ring-0.5',
        selected ? 'ring-indigo-500' : 'ring-black',
        selected ? 'ring-opacity-20' : 'ring-opacity-5',
      ].join(' ')}
      style={{ width: `${NODE_WIDTH}px`, height: `${NODE_HEIGHT}px` }}
      title={tooltip || label}
    >
      {targetPosition && <Handle
        type="target"
        position={targetPosition}
        isConnectable={isConnectable}
        style={{ visibility: 'hidden', border: 'none', height: 0, top: 0 }}
      />
}
      <div
        className={[
          'h-full',
          'text-center',
          // TODO can we remove the data call, do all data stuff in Job and Trigger?
          !data.hasChildren && 'items-center',
        ].filter(Boolean).join(' ')}
      >
        <div
          className={[
            'flex',
            !data.hasChildren && 'flex-col',
            'justify-center',
            'h-full',
            'text-center',
          ].filter(Boolean).join(' ')}
        >
          <p className={`line-clamp-2 align-middle ${labelClass}`}>{label}</p>
        </div>
      </div>
      {toolbar && <div
        className="flex flex-col w-fit mx-auto items-center opacity-0 
                      group-hover:opacity-100 transition duration-150 ease-in-out"
      >
        {/* TODO don't show this if ths node already has a placeholder child */}
        {toolbar()}
      </div>}
      <Handle
        type="source"
        position={sourcePosition}
        isConnectable={isConnectable}
        style={{ visibility: 'hidden', border: 'none', height: 0, bottom: 0 }}
      />
    </div>
  );
};

Node.displayName = 'JobNode';

export default memo(Node);
