import React from 'react';

export type TabSpec = {
  label: string;
  id: string;
  icon: React.JSXElementConstructor<React.SVGAttributes<SVGSVGElement>>;
};

export type TabsProps = {
  options: TabSpec[];
  onSelectionChange?: (newName: string) => void;
  collapsedVertical?: boolean; // New prop for collapsed state
  initialSelection?: string;
};

export const Tabs = ({
  options,
  onSelectionChange,
  collapsedVertical = false,
  initialSelection,
}: TabsProps) => {
  const [selected, setSelected] = React.useState(
    initialSelection || options[0]?.id
  );
  const [useDropdown, setUseDropdown] = React.useState(false);
  const containerRef = React.useRef<HTMLDivElement>(null);

  const handleSelectionChange = (name: string) => {
    setSelected(name);
    onSelectionChange?.(name);
  };

  const handleSelectChange = (event: React.ChangeEvent<HTMLSelectElement>) => {
    handleSelectionChange(event.target.value);
  };

  // Monitor container width to determine if dropdown should be used
  React.useEffect(() => {
    if (!containerRef.current) return;

    const observer = new ResizeObserver(entries => {
      const entry = entries[0];
      if (entry) {
        const containerWidth = entry.contentRect.width;
        // Rough calculation: each tab needs about 120px minimum
        const minWidthNeeded = options.length * 120;
        setUseDropdown(containerWidth < minWidthNeeded);
      }
    });

    observer.observe(containerRef.current);

    return () => observer.disconnect();
  }, [options.length]);

  if (collapsedVertical) {
    return (
      <div className="h-full w-12">
        <div className="bg-slate-100 p-1 rounded-lg h-full">
          <nav className="flex flex-col gap-1 h-full" aria-label="Tabs">
            {options.map(({ label, id, icon }) => {
              const isSelected = id === selected;

              return (
                <button
                  type="button"
                  key={id}
                  onClick={() => handleSelectionChange(id)}
                  className={`flex-1 rounded-md px-2 py-3 text-sm font-medium flex flex-col items-center justify-center transition-all duration-200 ${
                    isSelected
                      ? 'bg-white text-indigo-600'
                      : 'text-gray-500 hover:text-gray-700 hover:bg-slate-50'
                  }`}
                  aria-current={isSelected ? 'page' : undefined}
                  style={{
                    writingMode: 'vertical-rl',
                    textOrientation: 'mixed',
                  }}
                >
                  {React.createElement(icon, {
                    className: 'inline h-4 w-4 mb-1',
                  })}
                  <span className="text-xs transform rotate-180 whitespace-nowrap">
                    {label}
                  </span>
                </button>
              );
            })}
          </nav>
        </div>
      </div>
    );
  }

  // Responsive layout with dropdown for narrow containers
  return (
    <div className="w-full" ref={containerRef}>
      {useDropdown ? (
        // Mobile/narrow dropdown
        <div className="grid grid-cols-1">
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
        </div>
      ) : (
        // Wide container tabs - pill style
        <div className="bg-slate-100 p-1 rounded-lg">
          <nav className="flex gap-1" aria-label="Tabs">
            {options.map(({ label, id, icon }) => {
              const isSelected = id === selected;
              const widthClass = `flex-1`;

              return (
                <button
                  type="button"
                  key={id}
                  onClick={() => handleSelectionChange(id)}
                  className={`${widthClass} rounded-md px-3 py-2 text-sm font-medium flex items-center justify-center transition-all duration-200 ${
                    isSelected
                      ? 'bg-white text-indigo-600'
                      : 'text-gray-500 hover:text-gray-700 hover:bg-slate-50'
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
      )}
    </div>
  );
};
