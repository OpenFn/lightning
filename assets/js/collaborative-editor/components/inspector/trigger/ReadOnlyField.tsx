import type { ReactNode } from 'react';

interface ReadOnlyFieldProps {
  /** Field label rendered above the value box. */
  label: string;
  /** The read-only value (text) shown in the bordered box. */
  children: ReactNode;
}

/**
 * A labelled read-only value row used by the trigger show panels: a medium-weight
 * label above a bordered, muted value box. Keeps the "label + box" markup
 * identical across the cron and kafka resting panels.
 */
export function ReadOnlyField({ label, children }: ReadOnlyFieldProps) {
  return (
    <div className="space-y-2">
      <span className="block text-sm font-medium text-slate-900">{label}</span>
      <div
        className="rounded-lg border border-gray-200 bg-white px-3 py-2
          text-sm text-slate-500"
      >
        {children}
      </div>
    </div>
  );
}
