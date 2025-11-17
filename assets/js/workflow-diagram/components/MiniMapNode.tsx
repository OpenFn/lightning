import { ClockIcon, GlobeAltIcon } from '@heroicons/react/24/outline';
import type { MiniMapNodeProps } from '@xyflow/react';
import { memo } from 'react';

import { useWorkflowStore } from '../../workflow-store/store';
import useAdaptorIcons from '../useAdaptorIcons';
import getAdaptorName from '../util/get-adaptor-name';

type Trigger = {
  id: string;
  type: 'webhook' | 'cron';
};

type Job = {
  id: string;
  adaptor?: string;
};

const MinimapNode = ({
  x,
  y,
  width: _width,
  height: _height,
  id,
  selected: _selected,
}: MiniMapNodeProps) => {
  const { triggers, jobs } = useWorkflowStore();
  const adaptorIconsData = useAdaptorIcons();

  // Check if this node is a trigger by looking it up in the triggers array
  const trigger = triggers.find((trigger: Trigger) => trigger.id === id);
  const isTrigger = !!trigger;

  // For triggers, we'll use the appropriate icon
  if (isTrigger) {
    // Use the same icons as the main Trigger component
    const icon =
      trigger.type === 'webhook' ? (
        <GlobeAltIcon className="w-full h-full text-gray-500" />
      ) : (
        <ClockIcon className="w-full h-full text-gray-500" />
      );

    return (
      <g>
        <circle
          cx={x + 60}
          cy={y + 60}
          r={60}
          fill="white"
          stroke="#ccc"
          strokeWidth={8}
        />
        <foreignObject x={x + 30} y={y + 30} width={60} height={60}>
          {icon}
        </foreignObject>
      </g>
    );
  }

  // For jobs, we'll use the adaptor icon if available
  const job = jobs.find((job: Job) => job.id === id);
  const adaptor = job?.adaptor ? getAdaptorName(job.adaptor) : null;
  const icon =
    adaptor && adaptorIconsData && adaptor in adaptorIconsData
      ? adaptorIconsData[adaptor]?.square
      : null;

  // Fallback to rectangle if no icon is available
  return (
    <g>
      <rect
        x={x}
        y={y}
        width={120}
        height={120}
        fill="white"
        stroke="#ccc"
        strokeWidth={8}
        rx={20}
      />
      {icon && (
        <image x={x + 20} y={y + 20} width={80} height={80} href={icon} />
      )}
    </g>
  );
};

export default memo(MinimapNode);
