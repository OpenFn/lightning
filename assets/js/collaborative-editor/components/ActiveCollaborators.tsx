import { cn } from '../../utils/cn';
import { useAwareness } from '../hooks/useAwareness';
import { getAvatarInitials } from '../utils/avatar';

import { Tooltip } from './Tooltip';

function lessthanmin(val: number, mins: number) {
  const now = Date.now();
  const threshold = now - mins * 60 * 1000;
  return val > threshold;
}

interface ActiveCollaboratorsProps {
  className?: string;
}

export function ActiveCollaborators({ className }: ActiveCollaboratorsProps) {
  const remoteUsers = useAwareness({ cached: true });

  if (remoteUsers.length === 0) {
    return null;
  }

  return (
    <div className={cn('flex items-center gap-1.5', className)}>
      {remoteUsers.map(user => {
        const nameParts = user.user.name.split(/\s+/);
        const firstName = nameParts[0] || '';
        const lastName =
          nameParts.length > 1 ? nameParts[nameParts.length - 1] : '';

        const userForInitials = {
          first_name: firstName,
          last_name: lastName,
        };

        const initials = getAvatarInitials(userForInitials as any);

        const tooltipContent =
          user.connectionCount && user.connectionCount > 1
            ? `${user.user.name} (${user.user.email}) - ${user.connectionCount} tabs`
            : `${user.user.name} (${user.user.email})`;

        return (
          <Tooltip key={user.clientId} content={tooltipContent} side="right">
            <div
              className={`relative inline-flex items-center justify-center rounded-full border-2 ${user.lastSeen && lessthanmin(user.lastSeen, 0.2) ? 'border-green-500' : 'border-gray-500 '}`}
            >
              <div
                className="w-5 h-5 rounded-full flex items-center justify-center font-normal text-[9px] font-semibold text-white cursor-default"
                style={{
                  backgroundColor: user.user.color,
                  textShadow:
                    '1px 0 0 rgba(0, 0, 0, 0.5), 0 -1px 0 rgba(0, 0, 0, 0.5), 0 1px 0 rgba(0, 0, 0, 0.5), -1px 0 0 rgba(0, 0, 0, 0.5)',
                }}
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
