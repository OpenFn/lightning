import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/react';
import { useMemo } from 'react';

import { cn } from '../../utils/cn';

export function Breadcrumbs({ children }: { children: React.ReactNode[] }) {
  // Split breadcrumbs: if more than 1, hide all but the last in dropdown
  const { hiddenItems, visibleItems } = useMemo(() => {
    if (children.length > 1) {
      return {
        hiddenItems: children.slice(0, -1),
        visibleItems: children.slice(-1),
      };
    }
    return {
      hiddenItems: [],
      visibleItems: children,
    };
  }, [children]);

  const items = useMemo(() => {
    const result: React.ReactNode[] = [];

    // Add ellipsis dropdown if there are hidden items
    if (hiddenItems.length > 0) {
      result.push(<BreadcrumbDropdown key="dropdown" items={hiddenItems} />);
    }

    // Add visible items with separators
    visibleItems.forEach((child, i) => {
      const showSeparator = hiddenItems.length > 0 || i > 0;
      if (showSeparator) {
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
  }, [hiddenItems, visibleItems]);

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
            className="absolute left-0 z-[9999] mt-2 w-48 origin-top-left rounded-md bg-white shadow-lg outline-1 outline-black/5 transition data-closed:scale-95 data-closed:transform data-closed:opacity-0 data-enter:duration-100 data-enter:ease-out data-leave:duration-75 data-leave:ease-in"
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
