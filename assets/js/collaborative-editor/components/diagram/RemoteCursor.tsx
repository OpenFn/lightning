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
          d="M5.65376 12.3673L5.46026 12.4976L5.44561 12.7075L5.07907 21.2476L5.05896 21.6761L5.43874 21.5034L9.53826 19.7668L9.71372 19.6861L9.81905 19.5245L14.8446 12.6621L15.1695 12.2222L14.6252 12.1005L6.3 10.2801L5.65376 12.3673Z"
          fill={color}
          stroke="white"
          strokeWidth="1.5"
        />
      </svg>

      {/* User name label */}
      <div
        className={cn(
          'absolute left-5 top-0 whitespace-nowrap rounded px-2 py-1',
          'text-xs font-medium text-white shadow-md'
        )}
        style={{ backgroundColor: color }}
      >
        {name}
      </div>
    </div>
  );
}
