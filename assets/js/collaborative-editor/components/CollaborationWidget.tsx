/**
 * CollaborationWidget - Compact floating widget showing connection status
 * and online users
 */

import { useSocket } from '../../react/contexts/SocketProvider';
import { cn } from '../../utils/cn';
import { useAwarenessUsers } from '../hooks/useAwareness';
import { useSession } from '../hooks/useSession';

export function CollaborationWidget() {
  const { isConnected: socketConnected, connectionError } = useSocket();
  const { isConnected: yjsConnected, isSynced } = useSession();

  const users = useAwarenessUsers();

  const getStatusColor = () => {
    if (socketConnected && yjsConnected && isSynced) return 'bg-green-500';
    if (socketConnected && yjsConnected) return 'bg-yellow-500';
    return 'bg-red-500';
  };

  const getStatusText = () => {
    if (socketConnected && yjsConnected && isSynced) return 'Synced';
    if (socketConnected && yjsConnected) return 'Connected';
    if (socketConnected) return 'Socket only';
    return 'Disconnected';
  };

  return (
    <div className="fixed bottom-4 left-1/2 transform -translate-x-1/2 z-50">
      <div
        className="flex items-center gap-3 px-3 py-2 bg-white border 
                      border-gray-200 rounded-full shadow-md text-xs"
      >
        {/* Connection status */}
        <div className="flex items-center gap-2">
          <div className={cn('w-2 h-2 rounded-full', getStatusColor())} />
          <span className="text-gray-600 font-medium">{getStatusText()}</span>
        </div>

        {/* Separator */}
        {users.length > 0 && <div className="w-px h-3 bg-gray-300" />}

        {/* Online users */}
        {users.length > 0 && (
          <div className="flex items-center gap-1">
            <span className="text-gray-500">
              {users.length} user{users.length !== 1 ? 's' : ''}:
            </span>
            <div className="flex gap-1">
              {users.slice(0, 3).map(user => (
                <div
                  key={user.clientId}
                  className="flex items-center gap-1 px-2 py-0.5 
                             bg-gray-50 rounded-full"
                  title={`${user.user.name} (Client ${user.clientId})`}
                >
                  <div
                    className="w-1.5 h-1.5 rounded-full"
                    style={{ backgroundColor: user.user.color }}
                  />
                  <span className="text-gray-700 max-w-16 truncate text-xs">
                    {user.user.name}
                  </span>
                </div>
              ))}
              {users.length > 3 && (
                <span className="text-gray-400 px-1">
                  +{users.length - 3} more
                </span>
              )}
            </div>
          </div>
        )}

        {/* Error indicator */}
        {connectionError && (
          <>
            <div className="w-px h-3 bg-gray-300" />
            <span
              className="text-red-600 cursor-help"
              title={`Error: ${connectionError}`}
            >
              ⚠️
            </span>
          </>
        )}
      </div>
    </div>
  );
}
