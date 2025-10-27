import React, { useEffect, useRef, useState } from "react";

interface SearchableListProps {
  placeholder?: string;
  children: React.ReactNode;
  onSearch?: (query: string) => void;
  autoFocus?: boolean;
}

export function SearchableList({
  placeholder = "Search...",
  children,
  onSearch,
  autoFocus = true,
}: SearchableListProps) {
  const [query, setQuery] = useState("");
  const searchInputRef = useRef<HTMLInputElement>(null);

  // Auto-focus search input when mounted
  useEffect(() => {
    if (autoFocus && searchInputRef.current) {
      searchInputRef.current.focus();
    }
  }, [autoFocus]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newQuery = e.target.value;
    setQuery(newQuery);
    onSearch?.(newQuery);
  };

  const handleClear = () => {
    setQuery("");
    onSearch?.("");
    searchInputRef.current?.focus();
  };

  return (
    <div className="flex flex-col gap-3">
      {/* Search Input */}
      <div className="relative">
        <input
          ref={searchInputRef}
          type="text"
          value={query}
          onChange={handleChange}
          placeholder={placeholder}
          className="block w-full rounded-md border-secondary-300
            pl-10 pr-10 shadow-xs sm:text-sm
            focus:border-primary-300 focus:ring
            focus:ring-primary-200/50"
        />
        <div
          className="pointer-events-none absolute inset-y-0
            left-0 flex items-center pl-3"
        >
          <span className="hero-magnifying-glass h-5 w-5 text-gray-400" />
        </div>
        {query && (
          <button
            type="button"
            onClick={handleClear}
            className="absolute inset-y-0 right-0 flex
              items-center pr-3"
          >
            <span
              className="hero-x-mark h-5 w-5 text-gray-400
                hover:text-gray-600"
            />
          </button>
        )}
      </div>

      {/* Results */}
      <div className="max-h-96 overflow-y-auto">{children}</div>
    </div>
  );
}
