import type React from "react";

import { useSession } from "../contexts/SessionProvider";

export const UserAwareness: React.FC = () => {
  const { users, isConnected, isSynced } = useSession();

  return (
    <div
      className="flex items-center justify-between p-3 bg-gray-50 
                    border rounded-lg mb-4"
    >
      {/* Connection status */}
      <div className="flex items-center gap-2 text-sm">
        <div
          className={`w-2 h-2 rounded-full ${
            isConnected && isSynced
              ? "bg-green-500"
              : isConnected
                ? "bg-yellow-500"
                : "bg-red-500"
          }`}
        />
        <span className="text-gray-600">
          {isConnected && isSynced
            ? "Connected & Synced"
            : isConnected
              ? "Connected (Syncing...)"
              : "Disconnected"}
        </span>
      </div>

      {/* Online users */}
      <div className="flex items-center gap-2">
        <span className="text-sm text-gray-600">
          {users.length} user{users.length !== 1 ? "s" : ""} online:
        </span>
        <div className="flex gap-1">
          {users.map((user) => (
            <div
              key={user.clientId}
              className="flex items-center gap-1 px-2 py-1 bg-white 
                         rounded-full text-xs border"
              title={`${user.user.name} (Client ${user.clientId})`}
            >
              <div
                className="w-2 h-2 rounded-full"
                style={{ backgroundColor: user.user.color }}
              />
              <span className="text-gray-700 max-w-20 truncate">
                {user.user.name}
              </span>
            </div>
          ))}
        </div>

        {users.length === 0 && isConnected && (
          <span className="text-xs text-gray-400 italic">Just you</span>
        )}
      </div>
    </div>
  );
};
