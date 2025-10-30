import { useRemoteUsers } from "../hooks/useAwareness";
import { getAvatarInitials } from "../utils/avatar";

import { Tooltip } from "./Tooltip";

function lessthanmin(val: number, mins: number) {
  const now = Date.now();
  const threshold = now - mins * 60 * 1000;
  return val > threshold;
}

export function ActiveCollaborators() {
  const remoteUsers = useRemoteUsers();

  if (remoteUsers.length === 0) {
    return null;
  }

  return (
    <div className="flex items-center gap-1.5 ml-2">
      {remoteUsers.map(user => {
        const nameParts = user.user.name.split(" ");
        const firstName = nameParts[0] || "";
        const lastName = nameParts[nameParts.length - 1] || "";

        const userForInitials = {
          first_name: firstName,
          last_name: lastName,
        };

        const initials = getAvatarInitials(userForInitials as any);

        return (
          <Tooltip
            key={user.clientId}
            content={`${user.user.name} (${user.user.email})`}
            side="right"
          >
            <div
              className={`inline-flex items-center justify-center rounded-full border-2 ${user.lastSeen && lessthanmin(user.lastSeen, 2) ? "border-green-300" : "border-gray-300 "}`}
            >
              <div
                className="w-5 h-5 rounded-full flex items-center justify-center font-normal text-[9px] font-semibold text-white cursor-default"
                style={{ backgroundColor: user.user.color }}
              >
                {initials}
              </div>
            </div>
          </Tooltip>
        );
      })}
    </div>
  );
}
