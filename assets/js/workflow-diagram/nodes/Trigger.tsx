import React, { memo } from 'react';

import { Handle, Position } from 'react-flow-renderer';
import type { NodeProps } from 'react-flow-renderer';
import getTriggerLabels from '../util/get-trigger-labels';

type Trigger = any;
type Workflow = any;


const TriggerNode = ({
  data,
  isConnectable,
  sourcePosition = Position.Bottom,
}: NodeProps & {
  data: { label: string; trigger: Trigger; workflow: Workflow };
}): JSX.Element => {
  const { label, tooltip } = getTriggerLabels(data);

  const cursor =
    data.trigger.type === 'webhook' ? 'cursor-pointer' : 'cursor-default';

  return (
    <div
      className={`bg-white ${cursor} h-full py-1 px-1 rounded-md shadow-sm text-center text-xs ring-0.5 ring-black ring-opacity-5`}
      style={{ width: '150px'}}
    >
      <div className="flex flex-col items-center justify-center h-full ">
        <p
          title={tooltip}
          className="text-[0.6rem] italic text-ellipsis overflow-hidden whitespace-pre-line"
        >
          {label}
        </p>
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

TriggerNode.displayName = 'TriggerWorkflowNode';

export default memo(TriggerNode);
