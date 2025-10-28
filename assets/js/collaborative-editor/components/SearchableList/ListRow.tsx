import React from "react";

interface ListRowProps {
  icon?: React.ReactNode;
  title: string;
  description?: string;
  onClick?: () => void;
  selected?: boolean;
}

export function ListRow({
  icon,
  title,
  description,
  onClick,
  selected = false,
}: ListRowProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`
        w-full text-left px-3 py-2 rounded-md
        hover:bg-gray-100 focus:outline-none focus:bg-gray-100
        flex items-center gap-3 transition-colors
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
