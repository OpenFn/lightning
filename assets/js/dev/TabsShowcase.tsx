import { useState } from 'react';

import { Tabs } from '#/ui/Tabs';

// Mounted on /dev/components next to the HEEx version of the same tabs.
const options = [
  { value: 'log', label: 'Log' },
  { value: 'input', label: 'Input' },
  { value: 'output', label: 'Output' },
];

export const TabsShowcase = ({
  'data-size': size,
  'data-variant': variant = 'underline',
}: {
  'data-size': 'default' | 'small';
  'data-variant'?: 'underline' | 'pills';
}) => {
  const [value, setValue] = useState('log');

  return (
    <>
      <Tabs
        value={value}
        onChange={setValue}
        options={options}
        size={size}
        variant={variant}
        aria-label="Run"
      />
      <p className="py-3">{value} content</p>
    </>
  );
};
