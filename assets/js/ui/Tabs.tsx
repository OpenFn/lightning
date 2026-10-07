import type { FC, SVGProps } from 'react';

import { cn } from '#/utils/cn';

export interface TabOption<T extends string> {
  value: T;
  label: string;
  icon?: FC<SVGProps<SVGSVGElement>>;
}

interface TabsProps<T extends string> {
  value: T;
  onChange: (value: T) => void;
  options: TabOption<T>[];
  variant?: 'underline' | 'pills';
  size?: 'default' | 'small';
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
        className
      )}
    >
      {options.map(({ value: optionValue, label, icon: Icon }) => (
        <button
          key={optionValue}
          type="button"
          role="tab"
          aria-selected={value === optionValue}
          className="ui-tab"
          onClick={() => onChange(optionValue)}
        >
          {Icon && <Icon aria-hidden="true" className="h-5 w-5 mr-2" />}
          <span>{label}</span>
        </button>
      ))}
    </div>
  );
}
