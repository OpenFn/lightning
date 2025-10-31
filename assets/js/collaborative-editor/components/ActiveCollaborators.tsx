import { useRemoteUsers } from "../hooks/useAwareness";
// eslint-disable-next-line import/order
import { getAvatarInitials, splitName } from "../utils/avatar";
import CollaboratorAvatar from "./CollaboratorAvatar";

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
        const initials = getAvatarInitials(splitName(user.user.name));

        const tooltipContent =
          user.connectionCount && user.connectionCount > 1
            ? `${user.user.name} (${user.user.email}) - ${user.connectionCount} tabs`
            : `${user.user.name} (${user.user.email})`;

        return (
          <CollaboratorAvatar
            color={user.user.color}
            initials={initials}
            isActive={!!(user.lastSeen && lessthanmin(user.lastSeen, 2))}
            tooltip={tooltipContent}
          />
        );
      })}
    </div>
  );
}
