import type React from 'react';
import { useEffect, useRef } from 'react';

interface ListRowProps {
  icon?: React.ReactNode;
  title: string;
  description?: string;
  onClick?: () => void;
  selected?: boolean;
  focused?: boolean;
  id?: string;
}

export function ListRow({
  icon,
  title,
  description,
  onClick,
  selected = false,
  focused = false,
  id,
}: ListRowProps) {
  const buttonRef = useRef<HTMLButtonElement>(null);

  // Scroll focused item into view
  useEffect(() => {
    if (focused && buttonRef.current && buttonRef.current.scrollIntoView) {
      buttonRef.current.scrollIntoView({
        block: 'nearest',
        behavior: 'smooth',
      });
    }
  }, [focused]);

  return (
    <button
      ref={buttonRef}
      type="button"
      onClick={onClick}
      id={id}
      role="option"
      aria-label={`Select ${title} adaptor`}
      aria-selected={focused || selected}
      className={`
        w-full text-left px-3 py-2 rounded-md
        hover:bg-gray-100 focus:outline-none
        flex items-center gap-3 transition-colors
        ${focused ? 'bg-gray-100' : ''}
      `}
    >
      {icon && <div className="shrink-0">{icon}</div>}
      <div className="flex-1 min-w-0">
        <div className="font-normal text-gray-900">{title}</div>
        {description && (
          <div className="text-sm text-gray-500 line-clamp-2">
            {description}
          </div>
        )}
      </div>
      {selected && (
        <span className="hero-check h-5 w-5 text-primary-600 shrink-0" />
      )}
    </button>
  );
}
