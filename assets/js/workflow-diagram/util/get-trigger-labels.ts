import cronstrue from 'cronstrue';
import type { TriggerNode } from '../types';

type TriggerLabels = {
  label: string;
  tooltip: string;
};

export default ({ trigger }: TriggerNode): TriggerLabels => {
  switch (trigger.type) {
    case 'webhook':
      return {
        label: `When data is received at ${trigger.webhookUrl}`,
        tooltip: 'Click to copy webhook URL',
      };
    case 'cron':
      try {
        const label = cronstrue.toString(trigger.cronExpression);
        return {
          label,
          tooltip: label || '',
        };
      } catch (_error) {}
  }
  return { label: '', tooltip: '' };
};
