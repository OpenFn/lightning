import React, { memo } from 'react';
import { Position, NodeProps } from 'reactflow';
import Node from './Node';

type NodeData = any;

const PlaceholderJobNode = ({
  targetPosition = Position.Top,
  sourcePosition = Position.Bottom,
  selected,
  ...props
}: NodeProps<NodeData>) => {

  return (<Node
    {...props}
    selected={selected}
    label="New Job"
    outerClass={[
      'group',
      'bg-transparent',
      'cursor-pointer',
      'h-full',
      'p-1',
      'rounded-md',
      'shadow-sm',
      'text-center',
      'text-xs',
      'border-dashed',
      'border-2',
      'border-indigo-500',
      selected ? 'border-opacity-70' : 'border-opacity-30',
    ].join(' ')}
    labelClass={`text-indigo-500 ${selected ? "text-opacity-90" : "text-opacity-50"}`}
    targetPosition={targetPosition}
    sourcePosition={sourcePosition}
  />)
 
};

PlaceholderJobNode.displayName = 'PlaceholderJobNode';

export default memo(PlaceholderJobNode);
