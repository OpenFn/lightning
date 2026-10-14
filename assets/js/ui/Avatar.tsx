import { UserIcon } from '@heroicons/react/24/outline';
import { useState, type CSSProperties, type FC, type SVGProps } from 'react';

import { cn } from '#/utils/cn';

interface AvatarProps {
  firstName?: string | null | undefined;
  lastName?: string | null | undefined;
  src?: string | null | undefined;
  label?: string | undefined;
  icon?: FC<SVGProps<SVGSVGElement>>;
  size?: 'small' | 'medium' | 'large';
  className?: string;
  style?: CSSProperties;
}

// Styled by the shared .ui-avatar classes in css/ui/avatar.css, the same ones
// lib/lightning_web/components/ui/avatar.ex emits. Shows initials from the
// name, or the icon when there's no name. An image covers both, and is
// dropped if it fails to load so they show through. Hidden from screen
// readers unless it has a label, since a name usually sits beside it.
export function Avatar({
  firstName,
  lastName,
  src,
  label,
  icon: Icon = UserIcon,
  size = 'medium',
  className,
  style,
}: AvatarProps) {
  const [failedSrc, setFailedSrc] = useState<string | null>(null);
  const initials = [firstName, lastName]
    .map(name => name?.trim().charAt(0) ?? '')
    .join('')
    .toUpperCase();

  return (
    <span
      className={cn(
        'ui-avatar',
        size === 'small' && 'ui-avatar--small',
        size === 'large' && 'ui-avatar--large',
        className
      )}
      style={style}
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    >
      {initials || <Icon aria-hidden="true" className="ui-avatar__icon" />}
      {src && src !== failedSrc && (
        <img
          src={src}
          alt=""
          className="ui-avatar__image"
          onError={() => setFailedSrc(src)}
        />
      )}
    </span>
  );
}
