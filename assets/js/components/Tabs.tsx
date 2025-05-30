import React from 'react';

export const iconStyle =
  'inline cursor-pointer h-6 w-6 mr-1 hover:text-primary-600';

export type TabSpec = {
  label: string;
  id: string;
  icon: React.JSXElementConstructor<React.SVGAttributes<SVGSVGElement>>;
};

export type TabsProps = {
  options: TabSpec[];
  onSelectionChange?: (newName: string) => void;
  verticalCollapse?: boolean; // Made optional since we're using responsive design
  initialSelection?: string;
};

export const Tabs = ({
  options,
  onSelectionChange,
  initialSelection,
}: TabsProps) => {
  const [selected, setSelected] = React.useState(
    initialSelection || options[0]?.id
  );

  const handleSelectionChange = (name: string) => {
    if (name !== selected) {
      setSelected(name);
      onSelectionChange?.(name);
    }
  };

  return (
    <div className="w-full mb-2">
      <div className="border-b border-gray-200">
        <nav className="-mb-px flex" aria-label="Tabs">
          {options.map(({ label, id, icon }) => {
            const isSelected = id === selected;
            const widthClass = `w-1/${options.length}`;

            return (
              <button
                key={id}
                onClick={() => handleSelectionChange(id)}
                className={`${widthClass} border-b-2 px-1 py-4 text-center text-sm font-medium flex items-center justify-center ${
                  isSelected
                    ? 'border-indigo-500 text-indigo-600'
                    : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700'
                }`}
                aria-current={isSelected ? 'page' : undefined}
              >
                {React.createElement(icon, {
                  className: 'inline h-5 w-5 mr-2',
                })}
                <span>{label}</span>
              </button>
            );
          })}
        </nav>
      </div>
    </div>
  );
};
