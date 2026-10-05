import { ClockIcon, GlobeAltIcon } from '@heroicons/react/24/outline';
import { Position } from '@xyflow/react';
import cronstrue from 'cronstrue';
import { memo } from 'react';

import { lockClosedIcon } from '../components/trigger-icons';
import type { Lightning } from '../types';

import Node from './Node';

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
  // Read before the switch narrows it away: a snapshot taken while a
  // since-removed trigger type existed still reaches here, whatever the union
  // says.
  const declaredType: string = trigger.type;

  switch (trigger.type) {
    case 'webhook':
      return {
        label: 'Webhook trigger',
        sublabel: `On each request received`,
        tooltip: 'Click to copy webhook URL',
        primaryIcon: <GlobeAltIcon />,
        secondaryIcon: trigger.has_auth_method ? lockClosedIcon : null,
      };
    case 'cron':
      let sublabel = 'Not configured';
      try {
        if (trigger.cron_expression) {
          sublabel = cronstrue.toString(trigger.cron_expression);
        }
      } catch (_error) {
        sublabel = 'Invalid cron expression';
      }
      return {
        label: 'Cron trigger',
        sublabel,
        primaryIcon: <ClockIcon />,
        secondaryIcon: null,
      };
  }
  return { label: 'Unsupported trigger', sublabel: declaredType };
}
