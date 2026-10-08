import type { FC, ReactNode, SVGProps } from 'react';

import { Tooltip } from '#/components/Tooltip';
import { cn } from '#/utils/cn';

export interface TabOption<T extends string> {
  value: T;
  label: string;
  icon?: FC<SVGProps<SVGSVGElement>>;
  disabled?: boolean;
  disabledReason?: ReactNode;
}

interface TabsProps<T extends string> {
  value: T;
  onChange: (value: T) => void;
  options: TabOption<T>[];
  variant?: 'underline' | 'pills';
  size?: 'default' | 'small';
  orientation?: 'horizontal' | 'vertical';
  className?: string;
  'aria-label'?: string;
}

// Styled by the shared .ui-tabs/.ui-tab classes in css/ui/tabs.css, the same
// ones lib/lightning_web/components/ui/tabs.ex emits. The caller owns the
// selected value.
export function Tabs<T extends string>({
  value,
  onChange,
  options,
  variant = 'underline',
  size = 'default',
  orientation = 'horizontal',
  className,
  'aria-label': ariaLabel = 'Tabs',
}: TabsProps<T>) {
  return (
    <div
      role="tablist"
      aria-label={ariaLabel}
      className={cn(
        'ui-tabs',
        variant === 'pills' && 'ui-tabs--pills',
        size === 'small' && 'ui-tabs--small',
        orientation === 'vertical' && 'ui-tabs--vertical',
        className
      )}
    >
      {options.map(
        ({
          value: optionValue,
          label,
          icon: Icon,
          disabled,
          disabledReason,
        }) => {
          // aria-disabled, not disabled, keeps the tab focusable so the reason
          // is reachable by keyboard.
          const tab = (
            <button
              type="button"
              role="tab"
              aria-selected={value === optionValue}
              aria-disabled={disabled ? 'true' : undefined}
              className="ui-tab"
              onClick={() => {
                if (!disabled) onChange(optionValue);
              }}
            >
              {Icon && <Icon aria-hidden="true" className="ui-tab__icon" />}
              <span>{label}</span>
            </button>
          );
          return (
            <Tooltip
              key={optionValue}
              content={disabled ? disabledReason : null}
            >
              {tab}
            </Tooltip>
          );
        }
      )}
    </div>
  );
}
