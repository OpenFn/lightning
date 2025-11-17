import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/react';
import { useMemo } from 'react';

import { cn } from '../../utils/cn';

export function Breadcrumbs({ children }: { children: React.ReactNode[] }) {
  // Split: Last item is always the title (always visible)
  // Of the remaining breadcrumbs, show only the last one, hide the rest
  const { hiddenItems, visibleBreadcrumb, title } = useMemo(() => {
    if (children.length === 0) {
      return { hiddenItems: [], visibleBreadcrumb: null, title: null };
    }

    // Last child is the title
    const titleItem = children[children.length - 1];
    const breadcrumbs = children.slice(0, -1);

    if (breadcrumbs.length > 1) {
      // Hide all but the last breadcrumb
      return {
        hiddenItems: breadcrumbs.slice(0, -1),
        visibleBreadcrumb: breadcrumbs[breadcrumbs.length - 1],
        title: titleItem,
      };
    }

    return {
      hiddenItems: [],
      visibleBreadcrumb: breadcrumbs[0] ?? null,
      title: titleItem,
    };
  }, [children]);

  const items = useMemo(() => {
    const result: React.ReactNode[] = [];

    // Add ellipsis dropdown if there are hidden items
    if (hiddenItems.length > 0) {
      result.push(<BreadcrumbDropdown key="dropdown" items={hiddenItems} />);
    }

    // Add visible breadcrumb (if exists)
    if (visibleBreadcrumb) {
      // Only show separator if there are hidden items (ellipsis dropdown before this)
      if (hiddenItems.length > 0) {
        result.push(
          <span
            key="chevron-breadcrumb"
            className="hero-chevron-right-mini w-5 h-5 text-secondary-500"
          />
        );
      }
      result.push(
        <li key="visible-breadcrumb" className="flex items-center">
          {visibleBreadcrumb}
        </li>
      );
    }

    // Add title (with separator only if there's something before it)
    if (title) {
      // Show separator if there are hidden items OR a visible breadcrumb
      if (hiddenItems.length > 0 || visibleBreadcrumb !== null) {
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
  }, [hiddenItems, visibleBreadcrumb, title]);

  return (
    <nav className="flex" aria-label="Breadcrumb">
      <ol className="flex items-center space-x-2">{items}</ol>
    </nav>
  );
}

function BreadcrumbDropdown({ items }: { items: React.ReactNode[] }) {
  return (
    <li>
      <div className="flex items-center">
        <Menu as="div" className="relative">
          <MenuButton className="flex items-center text-sm font-medium text-gray-500 hover:text-gray-700">
            <span className="hero-ellipsis-horizontal h-5 w-5" />
          </MenuButton>
          <MenuItems
            transition
            className="absolute left-0 z-[99999] mt-2 w-48 origin-top-left rounded-md bg-white shadow-lg outline-1 outline-black/5 transition data-closed:scale-95 data-closed:transform data-closed:opacity-0 data-enter:duration-100 data-enter:ease-out data-leave:duration-75 data-leave:ease-in"
          >
            <div className="py-1">
              {items.map((item, index) => (
                <MenuItem key={index}>
                  <div className="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">
                    {item}
                  </div>
                </MenuItem>
              ))}
            </div>
          </MenuItems>
        </Menu>
      </div>
    </li>
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
