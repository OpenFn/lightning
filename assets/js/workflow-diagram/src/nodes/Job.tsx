import React, { memo, useState } from 'react';
import { Handle, Position, NodeProps } from 'react-flow-renderer';
import cc from 'classcat';

import PlusButton from './PlusButton';

type NodeData = any;

const JobNode = ({
  data,
  isConnectable,
  selected,
  targetPosition = Position.Top,
  sourcePosition = Position.Bottom,
}: NodeProps<NodeData>) => {
  return (
    <div
      className={cc([
        'group',
        'bg-white',
        'cursor-pointer',
        'h-full',
        'p-1',
        'rounded-md',
        'shadow-sm',
        'text-center',
        'text-xs',
        selected ? 'ring-2' : 'ring-0.5',
        selected ? 'ring-indigo-500' : 'ring-black',
        selected ? 'ring-opacity-20' : 'ring-opacity-5',
      ])}
      style={{ width: '150px'}}
      title={data?.label}
    >
      <Handle
        type="target"
        position={targetPosition}
        isConnectable={isConnectable}
        style={{ border: 'none', height: 0, top: 0 }}
      />

      <div
        className={cc([
          'h-full',
          'text-center',
          !data.hasChildren && 'items-center',
        ])}
      >
        <div
          className={cc([
            'flex',
            !data.hasChildren && 'flex-col',
            'justify-center',
            'h-full',
            'text-center',
          ])}
        >
          <p className="line-clamp-2 align-middle">{data?.label}</p>
        </div>
      </div>
      <div
        className="flex flex-col w-fit mx-auto items-center opacity-0 
                      group-hover:opacity-100 transition duration-150 ease-in-out"
      >
        <PlusButton />
      </div>
      <Handle
        type="source"
        position={sourcePosition}
        isConnectable={isConnectable}
        style={{ border: 'none', height: 0, top: 0 }}
      />
    </div>
  );
};

JobNode.displayName = 'JobNode';

export default memo(JobNode);
