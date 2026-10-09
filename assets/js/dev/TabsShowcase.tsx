import {
  ArrowDownOnSquareIcon,
  ArrowUpOnSquareIcon,
  DocumentTextIcon,
} from '@heroicons/react/24/outline';
import { useState } from 'react';

import { Tabs, type TabOption } from '#/ui/Tabs';
import { cn } from '#/utils/cn';

// Mounted on /dev/components next to the HEEx version of the same tabs.
// Props arrive as data- attributes, so booleans are the strings 'true'/'false'.
export const TabsShowcase = ({
  'data-size': size = 'default',
  'data-variant': variant = 'underline',
  'data-orientation': orientation = 'horizontal',
  'data-icons': icons = 'false',
  'data-disabled': disabled = 'false',
}: {
  'data-size'?: 'default' | 'small';
  'data-variant'?: 'underline' | 'pills';
  'data-orientation'?: 'horizontal' | 'vertical';
  'data-icons'?: string;
  'data-disabled'?: string;
}) => {
  const [value, setValue] = useState('log');
  const icon = (component: TabOption<string>['icon']) =>
    icons === 'true' && component ? { icon: component } : {};

  const options: TabOption<string>[] = [
    {
      value: 'log',
      label: 'Log',
      ...icon(DocumentTextIcon),
    },
    {
      value: 'input',
      label: 'Input',
      ...icon(ArrowDownOnSquareIcon),
      disabled: disabled === 'true',
      disabledReason: 'Pick a step',
    },
    {
      value: 'output',
      label: 'Output',
      ...icon(ArrowUpOnSquareIcon),
    },
  ];

  return (
    <div className={cn(orientation === 'vertical' && 'flex')}>
      <Tabs
        value={value}
        onChange={setValue}
        options={options}
        size={size}
        variant={variant}
        orientation={orientation}
        aria-label="Run"
      />
      <p className="py-3">{value} content</p>
    </div>
  );
};
