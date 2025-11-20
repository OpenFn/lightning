import React from 'react';

interface ListSectionProps {
  title: string;
  children: React.ReactNode;
}

export function ListSection({ title, children }: ListSectionProps) {
  return (
    <div className="mb-4 last:mb-0">
      <h3 className="px-3 py-2 text-sm text-gray-400">{title}</h3>
      <div className="space-y-1">{children}</div>
    </div>
  );
}
