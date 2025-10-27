import type { FC, SVGProps } from "react";

interface TabOption<T extends string> {
  value: T;
  label: string;
  icon?: FC<SVGProps<SVGSVGElement>>;
}

interface TabsProps<T extends string> {
  value: T;
  onChange: (value: T) => void;
  options: TabOption<T>[];
}

/**
 * Simple tabs component for switching between views
 */
export function Tabs<T extends string>({
  value,
  onChange,
  options,
}: TabsProps<T>) {
  return (
    <div className="border-b border-gray-200">
      <nav className="-mb-px flex w-full" aria-label="Tabs">
        {options.map(option => {
          const isSelected = value === option.value;
          const Icon = option.icon;

          return (
            <button
              key={option.value}
              onClick={() => onChange(option.value)}
              className={`
                group inline-flex items-center justify-center
                border-b-2 px-1 py-4 flex-1
                text-sm font-medium transition-colors
                ${
                  isSelected
                    ? "border-primary-500 text-primary-600"
                    : "border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700"
                }
              `}
              aria-current={isSelected ? "page" : undefined}
            >
              {Icon && (
                <Icon
                  className={`
                    -ml-0.5 mr-2 h-5 w-5
                    ${
                      isSelected
                        ? "text-primary-500"
                        : "text-gray-400 group-hover:text-gray-500"
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
