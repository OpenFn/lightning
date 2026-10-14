import { RocketLaunchIcon } from '@heroicons/react/24/outline';
import type { ComponentProps } from 'react';

import { Avatar } from '#/ui/Avatar';

type AvatarProps = ComponentProps<typeof Avatar>;

const cases: Record<string, AvatarProps> = {
  initials: { firstName: 'Ada', lastName: 'Lovelace' },
  'first-name': { firstName: 'Ada' },
  image: { src: '/images/user.png' },
  'broken-image': {
    firstName: 'Ada',
    lastName: 'Lovelace',
    src: '/images/missing.png',
  },
  icon: { icon: RocketLaunchIcon },
  'no-name': {},
};

// Mounted on /dev/components next to the HEEx version of the same avatars.
export const AvatarShowcase = ({
  'data-type': type = 'initials',
}: {
  'data-type'?: string;
}) => (
  <div className="flex items-center gap-4">
    {(['large', 'medium', 'small'] as const).map(size => (
      <Avatar key={size} size={size} {...cases[type]} />
    ))}
  </div>
);
