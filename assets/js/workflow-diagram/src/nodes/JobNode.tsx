import React, { memo, useState } from 'react';

import cc from 'classcat';
import type { NodeProps } from 'react-flow-renderer';
import { Handle, Position } from 'react-flow-renderer';
import { NodeData } from '../layout/types';

function PlusButton() {
  return (
    <button
      id="plusButton"
      className="transition duration-150 ease-in-out pointer-events-auto rounded-full
               bg-indigo-600 py-1 px-4 text-[0.8125rem] font-semibold leading-5 text-white hover:bg-indigo-500"
    >
      <svg
        id="plusIcon"
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        strokeWidth="1.5"
        stroke="currentColor"
        className="w-3 h-3"
      >
        <path strokeLinecap="round" strokeLinejoin="round" d="M12 6v12m6-6H6" />
      </svg>
    </button>
  );
}

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
