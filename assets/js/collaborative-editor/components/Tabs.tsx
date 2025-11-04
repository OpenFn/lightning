import type { FC, SVGProps } from 'react';

import { cn } from '#/utils/cn';

interface TabOption<T extends string> {
  value: T;
  label: string;
  icon?: FC<SVGProps<SVGSVGElement>>;
}

interface TabsProps<T extends string> {
  value: T;
  onChange: (value: T) => void;
  options: TabOption<T>[];
  variant?: 'pills' | 'underline';
  className?: string;
}

/**
 * Simple tabs component for switching between views
 *
 * Supports two visual styles:
 * - `underline` (default): Bottom border with underline indicator
 * - `pills`: Rounded background container with pill-style tabs
 */
export function Tabs<T extends string>({
  value,
  onChange,
  options,
  variant = 'underline',
  className,
}: TabsProps<T>) {
  if (variant === 'pills') {
    return (
      <div className={cn('bg-slate-100 p-1 rounded-lg', className)}>
        <nav className="flex gap-1" aria-label="Tabs">
          {options.map(option => {
            const isSelected = value === option.value;
            const Icon = option.icon;

            return (
              <button
                key={option.value}
                onClick={() => onChange(option.value)}
                className={`
                  flex-1 rounded-md px-3 py-2 text-sm font-medium
                  flex items-center justify-center transition-all duration-200
                  ${
                    isSelected
                      ? 'bg-white text-indigo-600'
                      : 'text-gray-500 hover:text-gray-700 hover:bg-slate-50'
                  }
                `}
                aria-current={isSelected ? 'page' : undefined}
              >
                {Icon && (
                  <Icon className="inline h-5 w-5 mr-2" aria-hidden="true" />
                )}
                <span>{option.label}</span>
              </button>
            );
          })}
        </nav>
      </div>
    );
  }

  // Underline variant
  return (
    <div className={className}>
      <nav
        className="flex flex-row space-x-6 job-viewer-tabs"
        aria-label="Tabs"
      >
        {options.map(option => {
          const isSelected = value === option.value;
          const Icon = option.icon;

          return (
            <button
              key={option.value}
              onClick={() => onChange(option.value)}
              className={`
                group inline-flex items-center
                border-b-2 px-1 py-1
                text-xs font-semibold leading-tight transition-colors
                ${
                  isSelected
                    ? 'border-primary-500 text-primary-600'
                    : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700'
                }
              `}
              aria-current={isSelected ? 'page' : undefined}
            >
              {Icon && (
                <Icon
                  className={`
                    -ml-0.5 mr-2 h-5 w-5
                    ${
                      isSelected
                        ? 'text-primary-500'
                        : 'text-gray-400 group-hover:text-gray-500'
                    }
                  `}
                  aria-hidden="true"
                />
              )}
              <span>{option.label}</span>
            </button>
          );
        })}
      </nav>
    </div>
  );
}
