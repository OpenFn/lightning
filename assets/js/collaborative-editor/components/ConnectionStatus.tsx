/**
 * ConnectionStatus - Shows the status of Socket and Yjs connections
 */

import { useSocket } from '../../react/contexts/SocketProvider';
import { useSession } from '../hooks/useSession';

export function ConnectionStatus() {
  const { isConnected: socketConnected, connectionError } = useSocket();
  const { isConnected: yjsConnected, isSynced } = useSession();

  const getStatusColor = (connected: boolean) => {
    return connected ? 'text-green-600' : 'text-red-600';
  };

  const getStatusIcon = (connected: boolean) => {
    return connected ? '✅' : '❌';
  };

  return (
    <div className="mb-4 p-3 bg-gray-50 border border-gray-200 rounded-lg">
      <h4 className="text-sm font-semibold text-gray-800 mb-2">
        Connection Status
      </h4>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-xs">
        <div className="flex items-center justify-between">
          <span>Socket:</span>
          <span className={getStatusColor(socketConnected)}>
            {getStatusIcon(socketConnected)}{' '}
            {socketConnected ? 'Connected' : 'Disconnected'}
          </span>
        </div>
        <div className="flex items-center justify-between">
          <span>Yjs Provider:</span>
          <span className={getStatusColor(yjsConnected && isSynced)}>
            {getStatusIcon(yjsConnected && isSynced)}{' '}
            {yjsConnected
              ? isSynced
                ? 'Synced'
                : 'Connected'
              : 'Disconnected'}
          </span>
        </div>
      </div>
      {connectionError && (
        <div className="mt-2 text-xs text-red-600">
          Socket Error: {connectionError}
        </div>
      )}
    </div>
  );
}
