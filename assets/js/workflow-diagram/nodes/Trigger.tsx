import React, { memo } from 'react';
import { Handle, Position } from 'reactflow';
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

  const width = 150;
  const height = 150;
  const styles = { fill: 'red', strokeWidth: 2, stroke: '#fff' };

  return (
    // <ellipse cx={width / 2} cy={height / 2} rx={width / 2} ry={height / 2} {...styles}/>
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
