import { useViewport } from '@xyflow/react';
import { useMemo } from 'react';

import { cn } from '../../../utils/cn';
import { useRemoteUsers } from '../../hooks/useAwareness';

import { denormalizePointerPosition } from './normalizePointer';

interface RemoteCursor {
  clientId: number;
  name: string;
  color: string;
  x: number;
  y: number;
}

export function RemoteCursors() {
  const remoteUsers = useRemoteUsers();
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

        return {
          clientId: user.clientId,
          name: user.user.name,
          color: user.user.color,
          x: screenPos.x,
          y: screenPos.y,
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

function RemoteCursor({ name, color, x, y }: RemoteCursorProps) {
  return (
    <div
      className="absolute transition-all duration-100 ease-out"
      style={{
        left: `${x}px`,
        top: `${y}px`,
        transform: 'translate(-4px, -12px)', // small shift to align pointer well
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
          d="m 4.580503,0.60395675 a 2,2 0 0 1 2.27,-0.42 v 0 L 22.780503,7.4039568 a 2,2 0 0 1 1.2,2.12 2.26,2.26 0 0 1 -1.8,2.0000002 l -5.58,1.13 -1.13,5.58 a 2.26,2.26 0 0 1 -2,1.8 h -0.25 a 2,2 0 0 1 -1.87,-1.2 l -7.19,-15.9600002 a 2,2 0 0 1 0.42,-2.27000005 z"
          fill="currentColor"
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
}
