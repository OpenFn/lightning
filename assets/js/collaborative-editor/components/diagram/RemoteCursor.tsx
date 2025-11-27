import { useViewport } from '@xyflow/react';
import { memo, useMemo } from 'react';

import { cn } from '../../../utils/cn';
import { useAwareness } from '../../hooks/useAwareness';

import { denormalizePointerPosition } from './normalizePointer';

interface RemoteCursor {
  clientId: number;
  name: string;
  color: string;
  x: number;
  y: number;
}

export function RemoteCursors() {
  const remoteUsers = useAwareness();
  const { x: tx, y: ty, zoom: tzoom } = useViewport();

  const cursors = useMemo<RemoteCursor[]>(() => {
    return remoteUsers
      .filter(user => user.cursor)
      .map(user => {
        const screenPos = denormalizePointerPosition(
          {
            x: user.cursor!.x,
            y: user.cursor!.y,
          },
          [tx, ty, tzoom]
        );

        // Round to nearest pixel to reduce micro-updates
        // that trigger unnecessary re-renders
        return {
          clientId: user.clientId,
          name: user.user.name,
          color: user.user.color,
          x: Math.round(screenPos.x),
          y: Math.round(screenPos.y),
        };
      });
  }, [remoteUsers, tx, ty, tzoom]);

  if (cursors.length === 0) {
    return null;
  }

  return (
    <div className="pointer-events-none absolute inset-0 z-50">
      {cursors.map(cursor => (
        <RemoteCursor
          key={cursor.clientId}
          name={cursor.name}
          color={cursor.color}
          x={cursor.x}
          y={cursor.y}
        />
      ))}
    </div>
  );
}

interface RemoteCursorProps {
  name: string;
  color: string;
  x: number;
  y: number;
}

// Memoize RemoteCursor to prevent re-renders when position hasn't changed
// significantly. This prevents CSS transitions from being interrupted by
// frequent viewport updates.
const RemoteCursor = memo(
  function RemoteCursor({ name, color, x, y }: RemoteCursorProps) {
    return (
      <div
        className="absolute transition-all duration-100 ease-out"
        style={{
          // Use transform for better GPU acceleration and smoother transitions
          // Translate by (x-2, y-2) to align pointer well
          transform: `translate(${x - 2}px, ${y - 2}px)`,
        }}
      >
        {/* Cursor pointer (SVG arrow) */}
        <svg
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
          className="drop-shadow-md"
        >
          <path
            d="M 4.580503,0.60395675 A 2,2 0 0 1 6.850503,0.18395675 V 0.18395675 L 22.780503,7.4039568 A 2,2 0 0 1 23.980503,9.5239568 A 2.26,2.26 0 0 1 22.180503,11.523957 L 16.600503,12.653957 L 15.470503,18.233957 A 2.26,2.26 0 0 1 13.470503,20.033957 H 13.220503 A 2,2 0 0 1 11.350503,18.833957 L 4.160503,2.8739568 A 2,2 0 0 1 4.580503,0.60395675 Z"
            fill={color}
            stroke="white"
            strokeWidth="1.5"
          />
        </svg>
        {/* User name label */}
        <div
          className={cn(
            'absolute left-7 top-0 whitespace-nowrap rounded px-2 py-1',
            'text-xs font-medium text-white shadow-md'
          )}
          style={{ backgroundColor: color }}
        >
          {name}
        </div>
      </div>
    );
  },
  // Custom comparison: only re-render if position changed by >1px
  // This prevents render storms from micro viewport changes
  (prev, next) => {
    return (
      prev.name === next.name &&
      prev.color === next.color &&
      Math.abs(prev.x - next.x) < 1 &&
      Math.abs(prev.y - next.y) < 1
    );
  }
);
