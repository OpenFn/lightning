import { useMemo } from 'react';

import { cn } from '../../utils/cn';

export function Breadcrumbs({ children }: { children: React.ReactNode[] }) {
  const items = useMemo(() => {
    const result: React.ReactNode[] = [];
    children.forEach((child, i) => {
      if (i > 0) {
        result.push(
          <span
            key={`chevron-${i}`}
            className="hero-chevron-right-mini w-5 h-5 text-secondary-500"
          />
        );
      }
      result.push(
        <li key={`breadcrumb-${i}`} className="flex items-center">
          {child}
        </li>
      );
    });
    return result;
  }, [children]);

  return (
    <nav className="flex" aria-label="Breadcrumb">
      <ol className="flex items-center space-x-2">{items}</ol>
    </nav>
  );
}
export function BreadcrumbLink({
  href,
  icon,
  children,
}: {
  href: string;
  icon?: string;
  children: React.ReactNode;
}) {
  return (
    <a
      href={href}
      className="text-gray-400 hover:text-gray-500 flex items-center"
    >
      {icon && <span className={cn(icon, 'w-5 h-5 text-secondary-500')}></span>}
      <span className={cn('font-medium text-gray-500', icon ? 'ml-2' : '')}>
        {children}
      </span>
    </a>
  );
}
export function BreadcrumbText({
  icon,
  children,
}: {
  icon?: string;
  children: React.ReactNode;
}) {
  return (
    <span className="flex items-center">
      {icon && <span className={cn(icon, 'w-5 h-5 text-secondary-500')}></span>}
      <span className={cn('font-medium text-gray-500', icon ? 'ml-2' : '')}>
        {children}
      </span>
    </span>
  );
}
