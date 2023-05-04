import React, { memo, useState } from 'react';
import { Handle, Position, NodeProps } from 'react-flow-renderer';

type NodeData = any;

const Node = ({
  label,
  labelClass = '',
  tooltip,
  interactive = true,
  data,
  isConnectable,
  selected,
  targetPosition,
  sourcePosition,
  toolbar
}: NodeProps<NodeData>) => {
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
      style={{ width: '150px', height: '40px' }}
      title={tooltip || label}
    >
      <Handle
        type="target"
        position={targetPosition}
        isConnectable={isConnectable}
        style={{ border: 'none', height: 0, top: 0 }}
      />

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
        style={{ border: 'none', height: 0, top: 0 }}
      />
    </div>
  );
};

Node.displayName = 'JobNode';

export default memo(Node);
