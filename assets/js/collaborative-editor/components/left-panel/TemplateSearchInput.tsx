import React, { useState, useCallback, useRef, useEffect } from 'react';

import { cn } from '#/utils/cn';

interface TemplateSearchInputProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  /** Focus the input when the component mounts (uses programmatic focus for accessibility) */
  focusOnMount?: boolean;
}

export function TemplateSearchInput({
  value,
  onChange,
  placeholder = 'Search templates...',
  focusOnMount = false,
}: TemplateSearchInputProps) {
  const [localValue, setLocalValue] = useState(value);
  const timeoutRef = useRef<NodeJS.Timeout | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    setLocalValue(value);
  }, [value]);

  // Programmatically focus the input when focusOnMount is true
  useEffect(() => {
    if (focusOnMount && inputRef.current) {
      // Small delay to ensure the panel animation has started
      const timer = setTimeout(() => {
        inputRef.current?.focus();
      }, 100);
      return () => clearTimeout(timer);
    }
  }, [focusOnMount]);

  const debouncedOnChange = useCallback(
    (newValue: string) => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
      timeoutRef.current = setTimeout(() => {
        onChange(newValue);
      }, 300);
    },
    [onChange]
  );

  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = e.target.value;
    setLocalValue(newValue);
    debouncedOnChange(newValue);
  };

  const handleClear = () => {
    setLocalValue('');
    onChange('');
  };

  return (
    <div className="relative">
      <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
        <span className="hero-magnifying-glass h-5 w-5 text-gray-400" />
      </div>
      <input
        ref={inputRef}
        type="text"
        value={localValue}
        onChange={handleChange}
        placeholder={placeholder}
        className={cn(
          'block w-full pl-10 pr-10 py-2 border border-gray-300 rounded-lg',
          'text-sm placeholder-gray-400',
          'focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent'
        )}
      />
      {localValue && (
        <button
          onClick={handleClear}
          className="absolute inset-y-0 right-0 pr-3 flex items-center"
          aria-label="Clear search"
        >
          <span className="hero-x-mark h-5 w-5 text-gray-400 hover:text-gray-600" />
        </button>
      )}
    </div>
  );
}
