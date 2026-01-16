import { useMemo } from 'react';

import { cn } from '../../utils/cn';

export function Breadcrumbs({ children }: { children: React.ReactNode[] }) {
  // Split: Last item is always the title (workflow name)
  // All other breadcrumbs are visible: Projects > Project Name > ...
  const { visibleBreadcrumbs, title } = useMemo(() => {
    if (children.length === 0) {
      return { visibleBreadcrumbs: [], title: null };
    }

    // Last child is the title (workflow name)
    const titleItem = children[children.length - 1];
    const breadcrumbs = children.slice(0, -1);

    return {
      visibleBreadcrumbs: breadcrumbs,
      title: titleItem,
    };
  }, [children]);

  const items = useMemo(() => {
    const result: React.ReactNode[] = [];

    // Add visible breadcrumbs
    visibleBreadcrumbs.forEach((breadcrumb, index) => {
      // Add separator - skip after first item (project picker pill)
      if (index > 1) {
        result.push(
          <span
            key={`chevron-breadcrumb-${index}`}
            className="hero-chevron-right-mini w-5 h-5 text-secondary-500"
          />
        );
      }
      result.push(
        <li
          key={`visible-breadcrumb-${index}`}
          className={cn('flex items-center', index === 0 && 'mr-3')}
        >
          {breadcrumb}
        </li>
      );
    });

    // Add title (with separator only if there's more than just project picker)
    if (title) {
      if (visibleBreadcrumbs.length > 1) {
        result.push(
          <span
            key="chevron-title"
            className="hero-chevron-right-mini w-5 h-5 text-secondary-500"
          />
        );
      }
      result.push(
        <li key="title" className="flex items-center">
          {title}
        </li>
      );
    }

    return result;
  }, [visibleBreadcrumbs, title]);

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
  onClick,
}: {
  href?: string;
  icon?: string;
  children: React.ReactNode;
  onClick?: (e: React.MouseEvent) => void;
}) {
  const content = (
    <>
      {icon && <span className={cn(icon, 'w-5 h-5 text-secondary-500')} />}
      <span className={cn('font-medium text-gray-500', icon ? 'ml-2' : '')}>
        {children}
      </span>
    </>
  );

  const className =
    'text-gray-400 hover:text-gray-500 flex items-center cursor-pointer';

  // If there's a real href, use a link (for navigation)
  if (href) {
    return (
      <a href={href} onClick={onClick} className={className}>
        {content}
      </a>
    );
  }

  // Otherwise, use a button (for actions)
  return (
    <button type="button" onClick={onClick} className={className}>
      {content}
    </button>
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

export function BreadcrumbProjectPicker({
  children,
  onClick,
}: {
  children: React.ReactNode;
  onClick?: (e: React.MouseEvent) => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex items-center gap-2 px-2.5 py-1.5 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 hover:border-gray-400 cursor-pointer transition-colors"
    >
      <span className="hero-folder h-4 w-4 text-gray-500" />
      {children}
    </button>
  );
}
