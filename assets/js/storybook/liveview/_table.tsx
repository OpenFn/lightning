import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

/**
 * Shared presentational clones of the `LightningWeb.Components.Table`
 * primitives (lib/lightning_web/components/table.ex), reused by the data-table
 * clone stories. Kept in sync with the markup in `Table.stories.tsx`.
 */
export const TR_CLASS = cn(
  'transition-colors duration-150 has-[td]:hover:bg-gray-50 last:rounded-b-lg',
  '[&>td:first-child]:py-4 [&>td:first-child]:pr-3 [&>td:first-child]:pl-4 [&>td:first-child]:sm:pl-6',
  '[&>th:first-child]:py-3.5 [&>th:first-child]:pr-3 [&>th:first-child]:pl-4 [&>th:first-child]:sm:pl-6',
  '[&>td:not(:first-child):not(:last-child)]:px-3 [&>td:not(:first-child):not(:last-child)]:py-4',
  '[&>th:not(:first-child):not(:last-child)]:px-3 [&>th:not(:first-child):not(:last-child)]:py-3.5',
  '[&>td:last-child]:relative [&>td:last-child]:py-4 [&>td:last-child]:pr-4 [&>td:last-child]:pl-3 [&>td:last-child]:sm:pr-6',
  '[&>th:last-child]:relative [&>th:last-child]:py-3.5 [&>th:last-child]:pr-4 [&>th:last-child]:pl-3 [&>th:last-child]:sm:pr-6'
);

export function Table({ children }: { children: ReactNode }) {
  return (
    <div className="bg-gray-50 shadow ring-1 ring-black/5 sm:rounded-lg">
      <table className="min-w-full divide-y divide-gray-200">{children}</table>
    </div>
  );
}

export function Tr({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return <tr className={cn(TR_CLASS, className)}>{children}</tr>;
}

export function Th({
  children,
  className,
  sortable,
  active,
  direction = 'asc',
}: {
  children?: ReactNode;
  className?: string;
  sortable?: boolean;
  active?: boolean;
  direction?: 'asc' | 'desc';
}) {
  return (
    <th
      scope="col"
      className={cn(
        'text-left text-sm font-semibold whitespace-nowrap text-gray-900 select-none',
        className
      )}
    >
      {sortable ? (
        <button
          type="button"
          className="group inline-flex cursor-pointer items-center gap-1"
        >
          {children}
          <span
            className={cn(
              'hero-chevron-down h-4 w-4 transition',
              active
                ? 'text-gray-900'
                : 'text-gray-300 group-hover:text-gray-400',
              active && direction === 'asc' ? 'rotate-180' : ''
            )}
          />
        </button>
      ) : (
        children
      )}
    </th>
  );
}

export function Td({
  children,
  className,
}: {
  children?: ReactNode;
  className?: string;
}) {
  return (
    <td
      className={cn(
        'text-sm text-gray-500 first:rounded-bl-lg last:rounded-br-lg',
        className
      )}
    >
      {children}
    </td>
  );
}

export function TableBody({ children }: { children: ReactNode }) {
  return (
    <tbody className="divide-y divide-gray-200 bg-white">{children}</tbody>
  );
}

/** The primary-tinted "project with access" chip used in several tables. */
export function AccessChip({ children }: { children: ReactNode }) {
  return (
    <span className="my-0.5 inline-flex items-center rounded-md bg-primary-50 p-1 text-xs font-medium ring-1 ring-gray-500/10 ring-inset">
      {children}
    </span>
  );
}

/** Inline monospace code chip (external IDs, keychain paths). */
export function CodeChip({ children }: { children: ReactNode }) {
  return (
    <code className="inline-block max-w-full truncate rounded bg-gray-100 px-1 py-0.5 text-xs">
      {children}
    </code>
  );
}

/** A small secondary "Actions" dropdown trigger used in table action columns. */
export function ActionsButton() {
  return (
    <button
      type="button"
      className="inline-flex items-center gap-1 rounded-md bg-white px-2.5 py-1.5 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-gray-300 ring-inset hover:bg-gray-50"
    >
      Actions
      <span className="hero-chevron-down-mini h-4 w-4 text-gray-400" />
    </button>
  );
}
