import React, { memo } from 'react';

import { Handle, Position } from 'reactflow';
import type { NodeProps } from 'reactflow';
import type { Trigger, Workflow } from '../types';
import cronstrue from 'cronstrue';

function descriptionFor({ trigger }: { trigger: Trigger }): string | null {
  switch (trigger.type) {
    case 'webhook':
      return `When data is received at ${trigger.webhookUrl}`;
    case 'cron':
      try {
        return cronstrue.toString(trigger.cronExpression);
      } catch (_error) {
        return null;
      }
    default:
      return null;
  }
}

const TriggerWorkflowNode = ({
  data,
  isConnectable,
  sourcePosition = Position.Bottom,
}: NodeProps & {
  data: { label: string; trigger: Trigger; workflow: Workflow };
}): JSX.Element => {
  const description = descriptionFor(data);
  const title =
    data.trigger.type === 'webhook'
      ? 'Click to copy webhook URL'
      : description || '';

  const cursor =
    data.trigger.type === 'webhook' ? 'cursor-pointer' : 'cursor-default';

  return (
    <div
      className={`bg-white ${cursor} h-full py-1 px-1 rounded-md shadow-sm text-center text-xs ring-0.5 ring-black ring-opacity-5`}
    >
      <div className="flex flex-col items-center justify-center h-full text-center">
        <p
          title={title}
          className="text-[0.6rem] italic text-ellipsis overflow-hidden whitespace-pre-line"
        >
          {description}
        </p>
      </div>
      <Handle
        type="source"
        position={sourcePosition}
        isConnectable={isConnectable}
        style={{ visibility: 'hidden', border: 'none', bottom: 0 }}
      />
    </div>
  );
};

TriggerWorkflowNode.displayName = 'TriggerWorkflowNode';

export default memo(TriggerWorkflowNode);
