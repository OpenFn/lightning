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
  verticalCollapse?: boolean; // Made optional since we're using responsive design
  initialSelection?: string;
};

export const Tabs = ({
  options,
  onSelectionChange,
  initialSelection,
}: TabsProps) => {
  const [selected, setSelected] = React.useState(initialSelection || options[0]?.id);

  const handleSelectionChange = (name: string) => {
    if (name !== selected) {
      setSelected(name);
      onSelectionChange?.(name);
    }
  };

  const handleSelectChange = (event: React.ChangeEvent<HTMLSelectElement>) => {
    handleSelectionChange(event.target.value);
  };

  return (
    <div className="w-full">
      {/* Mobile dropdown */}
      <div className="grid grid-cols-1 sm:hidden">
        <select
          aria-label="Select a tab"
          className="col-start-1 row-start-1 w-full appearance-none rounded-md bg-white py-2 pr-8 pl-3 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600"
          value={selected}
          onChange={handleSelectChange}
        >
          {options.map(({ label, id }) => (
            <option key={id} value={id}>
              {label}
            </option>
          ))}
        </select>
        <svg
          className="pointer-events-none col-start-1 row-start-1 mr-2 size-5 self-center justify-self-end fill-gray-500"
          viewBox="0 0 16 16"
          fill="currentColor"
          aria-hidden="true"
        >
          <path
            fillRule="evenodd"
            d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
            clipRule="evenodd"
          />
        </svg>
      </div>

      {/* Desktop tabs */}
      <div className="hidden sm:block">
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
                    className: 'inline h-5 w-5 mr-2' 
                  })}
                  <span>{label}</span>
                </button>
              );
            })}
          </nav>
        </div>
      </div>
    </div>
  );
};