import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

interface WithChildren {
  children: ReactNode;
  className?: string;
}

/**
 * Shared presentational scaffolding for the Storybook foundation and clone
 * stories. Kept intentionally small so individual stories stay readable.
 */
export function Showcase({ children, className }: WithChildren) {
  return (
    <div className={cn('flex flex-col gap-10 p-6 text-gray-900', className)}>
      {children}
    </div>
  );
}

export function Section({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children: ReactNode;
}) {
  return (
    <section className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <h3 className="text-xs font-semibold tracking-wider text-gray-500 uppercase">
          {title}
        </h3>
        {description ? (
          <p className="max-w-prose text-sm text-gray-600">{description}</p>
        ) : null}
      </div>
      {children}
    </section>
  );
}

export function Row({ children, className }: WithChildren) {
  return (
    <div className={cn('flex flex-wrap items-end gap-4', className)}>
      {children}
    </div>
  );
}

export function Specimen({
  label,
  children,
  className,
}: {
  label?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('flex flex-col items-center gap-2', className)}>
      <div className="flex min-h-12 items-center justify-center">{children}</div>
      {label ? (
        <span className="font-mono text-[11px] text-gray-500">{label}</span>
      ) : null}
    </div>
  );
}
