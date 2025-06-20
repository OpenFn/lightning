import { memo } from 'react';
import { Position } from '@xyflow/react';
import { ClockIcon, GlobeAltIcon } from '@heroicons/react/24/outline';
import { kafkaIcon, lockClosedIcon } from '../components/trigger-icons';
import cronstrue from 'cronstrue';

import Node from './Node';
import type { Lightning } from '../types';

type TriggerMeta = {
  label: string;
  sublabel?: string;
  tooltip?: string;
  primaryIcon?: React.ReactElement;
  secondaryIcon?: React.ReactElement | null;
};

const TriggerNode = ({
  sourcePosition = Position.Bottom,
  ...props
}: t.DistributedOmit<React.ComponentPropsWithoutRef<typeof Node>, 'data'> & {
  data: Lightning.TriggerNode;
}): JSX.Element => {
  // Do not remove yet, we might need this snippet of code when implementing issue #1121
  const { label, sublabel, tooltip, primaryIcon, secondaryIcon } =
    getTriggerMeta(props.data);
  return (
    <Node
      {...props}
      shape="circle"
      label={label}
      sublabel={sublabel}
      tooltip={tooltip}
      primaryIcon={primaryIcon}
      secondaryIcon={secondaryIcon}
      sourcePosition={sourcePosition}
      interactive={props.data.trigger.type === 'webhook'}
      // TODO: put back the toolbar when implementing issue #1121
      toolbar={false}
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
        primaryIcon: <GlobeAltIcon />,
        secondaryIcon: trigger.has_auth_method ? lockClosedIcon : null,
      };
    case 'kafka':
      return {
        label: 'Kafka trigger',
        sublabel: `On each message consumed from the cluster`,
        primaryIcon: kafkaIcon,
        secondaryIcon: trigger.has_auth_method ? lockClosedIcon : null,
      };
    case 'cron':
      try {
        return {
          label: 'Cron trigger',
          sublabel: cronstrue.toString(trigger.cron_expression),
          primaryIcon: <ClockIcon />,
          secondaryIcon: null,
        };
      } catch (_error) { }
  }
  return { label: '', sublabel: '' };
}
