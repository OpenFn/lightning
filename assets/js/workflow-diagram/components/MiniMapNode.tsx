import { ClockIcon, GlobeAltIcon } from '@heroicons/react/24/outline';
import type { MiniMapNodeProps } from '@xyflow/react';
import { memo } from 'react';

import { useAdaptorIconUrl } from '#/collaborative-editor/hooks/useAdaptors';

import { useWorkflowStore } from '../../workflow-store/store';

type Trigger = {
  id: string;
  type: 'webhook' | 'cron' | 'kafka';
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

  // Check if this node is a trigger by looking it up in the triggers array
  const trigger = triggers.find((trigger: Trigger) => trigger.id === id);
  const isTrigger = !!trigger;
  const job = jobs.find((job: Job) => job.id === id);
  const icon = useAdaptorIconUrl(job?.adaptor);

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
