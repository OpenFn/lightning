import { useRemoteUsers } from "../hooks/useAwareness";
import { getAvatarInitials, splitName } from "../utils/avatar";
import CollaboratorAvatar from "./CollaboratorAvatar";

interface UserAwarenessProps {
  /**
   * The job ID to filter users by.
   * When provided, only shows users who are editing this specific job.
   * When omitted, shows all remote users.
   */
  jobId?: string | null;
}

/**
 * UserAwareness component shows how many users are currently editing a job.
 * This is a simplified version focused on showing editor presence counts.
 *
 * @example
 * ```tsx
 * // Show users editing a specific job
 * <UserAwareness jobId="job-123" />
 *
 * // Show all remote users
 * <UserAwareness />
 * ```
 */
export function UserAwareness({ jobId }: UserAwarenessProps) {
  const remoteUsers = useRemoteUsers(jobId);
  const userCount = remoteUsers.length;

  // Don't show anything if no other users are present
  if (userCount === 0) {
    return null;
  }

  return (
    <div className="flex items-center gap-2 px-2 py-1 text-xs text-gray-600 bg-gray-50 rounded">
      <div className="flex -space-x-1">
        {remoteUsers.map(user => (
          <CollaboratorAvatar
            color={user.user.color}
            initials={getAvatarInitials(splitName(user.user.name))}
            isActive={true}
            tooltip={user.user.name}
          />
        ))}
      </div>
      <span>
        {userCount} {userCount === 1 ? "user" : "users"} editing this file
      </span>
    </div>
  );
}
