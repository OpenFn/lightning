import { useState, useRef, useEffect } from 'react';

const LOG_LEVELS = ['debug', 'info', 'warn', 'error'] as const;
type LogLevel = (typeof LOG_LEVELS)[number];

interface LogLevelFilterProps {
  selectedLevel: LogLevel;
  onLevelChange: (level: LogLevel) => void;
}

export function LogLevelFilter({
  selectedLevel,
  onLevelChange,
}: LogLevelFilterProps) {
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close dropdown when clicking outside
  useEffect(() => {
    if (!isOpen) return;

    function handleClickOutside(event: MouseEvent) {
      if (
        dropdownRef.current &&
        !dropdownRef.current.contains(event.target as Node)
      ) {
        setIsOpen(false);
      }
    }

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [isOpen]);

  return (
    <div ref={dropdownRef} className="relative z-50">
      <button
        type="button"
        className="grid w-full cursor-pointer grid-cols-1 bg-inherit text-left text-xs text-inherit opacity-75 hover:opacity-100"
        onClick={() => setIsOpen(!isOpen)}
        aria-haspopup="listbox"
        aria-expanded={isOpen}
      >
        <span className="col-start-1 row-start-1 truncate pr-6 flex items-center gap-1">
          <span
            className="hero-adjustments-vertical size-4"
            aria-hidden="true"
          />
          <span>{selectedLevel}</span>
        </span>
        <span
          className="hero-chevron-down col-start-1 row-start-1 size-4 self-center justify-self-end"
          aria-hidden="true"
        />
      </button>

      {isOpen && (
        <ul
          className="absolute z-10 mt-1 max-h-60 min-w-full w-max overflow-auto rounded-md bg-slate-600 py-1 text-base shadow-lg ring-1 ring-black/5 focus:outline-none sm:text-sm"
          role="listbox"
        >
          {LOG_LEVELS.map(level => (
            <li
              key={level}
              className="relative cursor-default select-none py-2 pl-8 pr-4 hover:bg-slate-500"
              role="option"
              onClick={() => {
                onLevelChange(level);
                setIsOpen(false);
              }}
            >
              <span
                className={`block truncate ${
                  level === selectedLevel ? 'font-semibold' : 'font-normal'
                }`}
              >
                {level}
              </span>
              {level === selectedLevel && (
                <span className="absolute inset-y-0 left-0 flex items-center pl-1.5">
                  <span className="hero-check size-5" aria-hidden="true" />
                </span>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
