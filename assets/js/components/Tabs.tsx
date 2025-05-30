import React from 'react';

export const iconStyle = 'inline cursor-pointer h-6 w-6 mr-1 hover:text-primary-600';

export type TabSpec = {
  label: string;
  id: string;
  icon: React.JSXElementConstructor<React.SVGAttributes<SVGSVGElement>>;
};

export type TabsProps = {
  options: TabSpec[];
  onSelectionChange?: (newName: string) => void;
  verticalCollapse: boolean;
  initialSelection?: String;
};

export const Tabs = ({
  options,
  onSelectionChange,
  verticalCollapse,
  initialSelection,
}: TabsProps) => {
  const [selected, setSelected] = React.useState(initialSelection);

  const handleSelectionChange = (name: string) => {
    if (name !== selected) {
      setSelected(name);
      onSelectionChange?.(name);
    }
  };

  const commonStyle = 'flex';
  const horizStyle = 'flex-space-x-2 w-full';
  const vertStyle = 'flex-space-y-2';

  const style: React.CSSProperties = verticalCollapse
    ? {
      writingMode: 'vertical-rl',
      textOrientation: 'mixed',
    }
    : {};

  return (
    <nav
      className={`${commonStyle} ${verticalCollapse ? vertStyle : horizStyle}`}
      aria-label="Tabs"
      style={style}
    >
      {options.map(({ label, id, icon }) => {
        const style =
          id === selected
            ? 'bg-primary-50 text-gray-700'
            : 'text-gray-400 hover:text-gray-700';
        return (
          <div
            key={id}
            onClick={() => handleSelectionChange(id)}
            className={`${style} select-none rounded-md px-3 py-2 text-sm font-medium cursor-pointer flex-row whitespace-nowrap`}
          >
            {React.createElement(icon, { className: iconStyle })}
            <span className="align-bottom">{label}</span>
          </div>
        );
      })}
    </nav>
  );
};