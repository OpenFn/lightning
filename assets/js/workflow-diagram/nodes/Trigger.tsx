import React, { memo } from 'react';
import { Position } from 'reactflow';
import { ClockIcon, GlobeAltIcon } from '@heroicons/react/24/outline';
import cronstrue from 'cronstrue';

import PlusButton from '../components/PlusButton';
import Node from './Node';
import type { Lightning } from '../types';

type TriggerMeta = {
  label: string;
  sublabel?: string;
  tooltip?: string;
  icon?: typeof ClockIcon | typeof GlobeAltIcon;
};

const TriggerNode = ({
  sourcePosition = Position.Bottom,
  ...props
}): JSX.Element => {
  const toolbar = () => props.data?.allowPlaceholder && <PlusButton />;
  const { label, sublabel, tooltip, icon } = getTriggerMeta(
    props.data as Lightning.TriggerNode
  );
  return (
    <Node
      {...props}
      shape="circle"
      label={label}
      sublabel={sublabel}
      tooltip={tooltip}
      icon={icon}
      sourcePosition={sourcePosition}
      interactive={props.data.trigger.type === 'webhook'}
      toolbar={toolbar}
    />
  );
};

TriggerNode.displayName = 'TriggerWorkflowNode';

export default memo(TriggerNode);

function getTriggerMeta(trigger: Lightning.TriggerNode): TriggerMeta {
  switch (trigger.type) {
    case 'webhook':
      return {
        label: 'Webhook trigger',
        sublabel: `On each request received`,
        tooltip: 'Click to copy webhook URL',
        icon: <GlobeAltIcon />,
      };
    case 'cron':
      try {
        return {
          label: 'Cron trigger',
          sublabel: cronstrue.toString(trigger.cron_expression),
          icon: <ClockIcon />,
        };
      } catch (_error) {}
  }
  return { label: '', sublabel: '' };
}
