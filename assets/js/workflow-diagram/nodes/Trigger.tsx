import React, { memo } from 'react';
import { Position } from 'reactflow';
import type { NodeProps } from 'reactflow';

import getTriggerLabels from '../util/get-trigger-labels';
import Node from './Node';

type Trigger = any;
type Workflow = any;
const TriggerNode = ({
  sourcePosition = Position.Bottom,
  ...props
}: NodeProps & {
  data: { label: string; trigger: Trigger; workflow: Workflow };
}): JSX.Element => {
  const { label, tooltip } = getTriggerLabels(props.data);

  return (
    <Node
      {...props}
      shape="circle"
      label={label}
      tooltip={tooltip}
      sourcePosition={sourcePosition}
      interactive={props.data.trigger.type === 'webhook'}
    />
  );
};

TriggerNode.displayName = 'TriggerWorkflowNode';

export default memo(TriggerNode);
