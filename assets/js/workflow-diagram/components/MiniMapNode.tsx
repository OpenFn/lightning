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

/**
 * MiniMap node renderer for workflow diagrams.
 *
 * This component is shared between Phoenix LiveView and Collaborative Editor:
 * - Phoenix LiveView: Uses Zustand store (no props needed)
 * - Collaborative Editor: Pass jobs/triggers as props
 *
 * @param jobs - Optional jobs array (falls back to useWorkflowStore if not
 *   provided)
 * @param triggers - Optional triggers array (falls back to useWorkflowStore
 *   if not provided)
 *
 * @example
 * // Phoenix LiveView usage (store-based)
 * <MiniMap nodeComponent={MiniMapNode} />
 *
 * @example
 * // Collaborative Editor usage (props-based)
 * <MiniMap
 *   nodeComponent={(props) => (
 *     <MiniMapNode {...props} jobs={jobs} triggers={triggers} />
 *   )}
 * />
 */
const MiniMapNode = ({
  x,
  y,
  width: _width,
  height: _height,
  id,
  selected: _selected,
  jobs: propJobs,
  triggers: propTriggers,
}: MiniMapNodeProps & { jobs?: Job[]; triggers?: Trigger[] }) => {
  // Fallback to store when props not provided (Phoenix LiveView pattern)
  const storeData = useWorkflowStore();
  const jobs = propJobs ?? storeData.jobs;
  const triggers = propTriggers ?? storeData.triggers;
  const adaptorIconsData = useAdaptorIcons();

  // Check if this node is a trigger by looking it up in the triggers array
  const trigger = triggers.find((trigger: Trigger) => trigger.id === id);
  const isTrigger = !!trigger;

  // For triggers, we'll use the appropriate icon
  if (isTrigger) {
    // Use the same icons as the main Trigger component
    // A historical snapshot can still hold a trigger type we no longer
    // support. Drawing it with the cron icon would assert something untrue, so
    // an unrecognised type gets no icon rather than the wrong one.
    // Read before narrowing: a snapshot can hold a type the union no longer
    // lists. Same shape as nodes/Trigger.tsx.
    const declaredType: string = trigger.type;

    const icon =
      declaredType === 'webhook' ? (
        <GlobeAltIcon className="w-full h-full text-gray-500" />
      ) : declaredType === 'cron' ? (
        <ClockIcon className="w-full h-full text-gray-500" />
      ) : null;

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

export default memo(MiniMapNode);
