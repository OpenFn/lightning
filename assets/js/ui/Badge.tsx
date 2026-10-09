import {
  forwardRef,
  type CSSProperties,
  type HTMLAttributes,
  type MouseEventHandler,
} from 'react';

import { cn } from '#/utils/cn';

const COLORS = {
  neutral: 'ui-badge--neutral',
  success: 'ui-badge--success',
  warning: 'ui-badge--warning',
  danger: 'ui-badge--danger',
  info: 'ui-badge--info',
  brand: 'ui-badge--brand',
  orange: 'ui-badge--orange',
  dark: 'ui-badge--dark',
} as const;

export type BadgeColor = keyof typeof COLORS;

interface BadgeOptions {
  color?: BadgeColor | null | undefined;
  size?: 'default' | 'small' | undefined;
  mono?: boolean | undefined;
  dot?: boolean | undefined;
  className?: string | undefined;
}

// The badge class list, for real buttons and links that need the look.
// `interactive` adds hover and focus styles.
export function badgeClassName({
  color,
  size,
  mono,
  dot,
  interactive,
  className,
}: BadgeOptions & { interactive?: boolean | undefined }) {
  return cn(
    'ui-badge',
    COLORS[color ?? 'neutral'],
    size === 'small' && 'ui-badge--small',
    mono && 'ui-badge--mono',
    dot && 'ui-badge--dot',
    interactive && 'ui-badge--interactive',
    className
  );
}

type RemoveProps =
  | {
      onRemove: MouseEventHandler<HTMLButtonElement>;
      removeLabel: string;
      removeDisabled?: boolean | undefined;
    }
  | { onRemove?: never; removeLabel?: never; removeDisabled?: never };

type BadgeProps = BadgeOptions &
  RemoveProps &
  Omit<HTMLAttributes<HTMLSpanElement>, 'color'> & {
    pulse?: boolean | undefined;
    icon?: string | undefined;
    dotStyle?: CSSProperties | undefined;
  };

// A badge is a look, never a role: this is a label. Styled by the shared
// .ui-badge classes in css/ui/badge.css, the same ones
// lib/lightning_web/components/ui/badge.ex emits. Forwards its ref and rest
// props so it can sit inside a Radix Tooltip trigger.
export const Badge = forwardRef<HTMLSpanElement, BadgeProps>(function Badge(
  {
    color,
    size,
    mono,
    dot,
    pulse,
    icon,
    dotStyle,
    className,
    onRemove,
    removeLabel,
    removeDisabled,
    children,
    ...rest
  },
  ref
) {
  return (
    <span
      ref={ref}
      className={badgeClassName({ color, size, mono, dot, className })}
      {...rest}
    >
      {dot && (
        <span className="ui-badge__dot" style={dotStyle}>
          {pulse && <span className="ui-badge__pulse" />}
        </span>
      )}
      {icon && (
        <span className={cn(icon, 'ui-badge__icon')} aria-hidden="true" />
      )}
      {children}
      {onRemove && (
        <button
          type="button"
          className="ui-badge__remove"
          aria-label={removeLabel}
          disabled={removeDisabled}
          onClick={onRemove}
        >
          <span className="hero-x-mark-micro h-3 w-3" aria-hidden="true" />
        </button>
      )}
    </span>
  );
});
