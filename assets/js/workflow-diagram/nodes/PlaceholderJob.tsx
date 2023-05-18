import React, { memo, useCallback, useRef } from 'react';
import { Handle, NodeProps, Position } from 'reactflow';
import { CheckCircleIcon, XMarkIcon } from '@heroicons/react/24/outline'
import { NODE_HEIGHT, NODE_WIDTH } from '../constants';

type NodeData = any;

const iconStyle = "mx-1 text-primary-500 hover:text-primary-900"

// Dispatch an event up to the WorkflowDiagram
// This works better than interfacing to the store correctly
// because the Workflow Diagram can control selection
const dispatch = (el: HTMLElement, eventName: 'commit-placeholder' | 'cancel-placeholder', data: Record<string, unknown>) => {
  const e = new CustomEvent(eventName, {
    bubbles: true,
    detail: data
  });
  el.dispatchEvent(e);
}

const PlaceholderJobNode = ({
  id,
  selected,
}: NodeProps<NodeData>) => {
  const textRef = useRef<HTMLInputElement>()

  const handleKeyDown = (evt) => {
    if (evt.code === 'Enter') {
      handleCommit();  
    }
    if (evt.code === 'Escape') {
      handleCancel();
    }
  };

  // TODO what if a name hasn't been entered?
  const handleCommit = useCallback(() => {
    if (textRef.current) {
      dispatch(textRef.current, 'commit-placeholder', { id,  name:  textRef.current.value })
    }
  }, [textRef])

  const handleCancel = useCallback(() => {
    if (textRef.current) {
      dispatch(textRef.current, 'cancel-placeholder', { id })
    }
  }, [textRef])

  return (
    <div
      className={[
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
        selected ? 'border-opacity-70' : 'border-opacity-30'
      ].join(' ')}
      style={{ width: `${NODE_WIDTH}px`, height: `${NODE_HEIGHT}px` }}
    >
      <Handle
        type="target"
        position={Position.Top}
        isConnectable
        style={{ visibility: 'hidden', border: 'none', height: 0, top: 0 }}
      />
      <div
        className={[
          'h-full',
          'text-center',
          'items-center',
        ].filter(Boolean).join(' ')}
      >
        <div
          className={[
            'flex',
            'flex-row',
            'justify-center',
            'h-full',
            'text-center',
          ].filter(Boolean).join(' ')}
        >
          <XMarkIcon className={`${iconStyle}`} title="Cancel creation of this job" onClick={handleCancel}/>
          <input
            type="text"
            ref={textRef}
            autoFocus
            data-placeholder={id}
            className={['line-clamp-2', 'align-middle','focus:outline-none','focus:ring-0', 'border-none', 'bg-transparent', 'text-center', 'text-xs'].join(' ')}
            onKeyDown={handleKeyDown}
          />
          <CheckCircleIcon className={`${iconStyle}`} title="Create this job" onClick={handleCommit}/>
        </div>
      </div>
    </div>
  );
};

PlaceholderJobNode.displayName = 'PlaceholderJobNode';

export default memo(PlaceholderJobNode);
