import { memo } from 'react';
import type { MiniMapNodeProps } from '@xyflow/react';
import { useWorkflowStore } from '../../workflow-store/store';
import useAdaptorIcons from '../useAdaptorIcons';
import getAdaptorName from '../util/get-adaptor-name';
import { ClockIcon, GlobeAltIcon } from '@heroicons/react/24/outline';

type Trigger = {
  id: string;
  type: 'webhook' | 'cron';
};

type Job = {
  id: string;
  adaptor?: string;
};

const CustomMinimapNode = ({
  x,
  y,
  width,
  height,
  id,
  selected,
}: MiniMapNodeProps) => {
  const { triggers, jobs } = useWorkflowStore();
  const adaptorIconsData = useAdaptorIcons();
  
  // Check if this node is a trigger by looking it up in the triggers array
  const trigger = triggers.find((trigger: Trigger) => trigger.id === id);
  const isTrigger = !!trigger;
  
  // For triggers, we'll use the appropriate icon
  if (isTrigger) {
    // Use the same icons as the main Trigger component
    const icon = trigger.type === 'webhook' ? (
      <GlobeAltIcon className="w-full h-full text-gray-500" />
    ) : (
      <ClockIcon className="w-full h-full text-gray-500" />
    );

    return (
      <g>
        <circle
          cx={x + width / 2}
          cy={y + height / 2}
          r={Math.min(width, height) / 2}
          fill="white"
          stroke={selected ? '#6366f1' : '#b1b1b7'}
          strokeWidth={selected ? 2 : 1}
        />
        <foreignObject
          x={x + width * 0.2}
          y={y + height * 0.2}
          width={width * 0.6}
          height={height * 0.6}
        >
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

  if (icon) {
    return (
      <image
        x={x}
        y={y}
        width={width}
        height={height}
        href={icon}
        stroke={selected ? '#6366f1' : '#b1b1b7'}
        strokeWidth={selected ? 2 : 1}
      />
    );
  }
  
  // Fallback to rectangle if no icon is available
  return (
    <rect
      x={x}
      y={y}
      width={width}
      height={height}
      fill="#ccc"
      stroke={selected ? '#6366f1' : '#b1b1b7'}
      strokeWidth={selected ? 2 : 1}
      rx={2}
    />
  );
};

export default memo(CustomMinimapNode);
