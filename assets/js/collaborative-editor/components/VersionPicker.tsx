import { useState, useRef, useEffect } from 'react';
import { createPortal } from 'react-dom';

interface VersionPickerProps {
  versions: string[];
  selectedVersion: string;
  onVersionChange: (version: string) => void;
}

/**
 * Custom searchable version picker
 * Allows users to search and select from available versions
 */
export function VersionPicker({
  versions,
  selectedVersion,
  onVersionChange,
}: VersionPickerProps) {
  const [query, setQuery] = useState('');
  const [isOpen, setIsOpen] = useState(false);
  const wrapperRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const dropdownRef = useRef<HTMLUListElement>(null);
  const [dropdownPosition, setDropdownPosition] = useState({
    top: 0,
    left: 0,
    width: 0,
  });

  // Filter versions based on search query
  const filteredVersions =
    query === ''
      ? versions
      : versions.filter(version => {
          return version.toLowerCase().includes(query.toLowerCase());
        });

  // Update dropdown position when opening
  useEffect(() => {
    if (isOpen && inputRef.current) {
      const rect = inputRef.current.getBoundingClientRect();
      setDropdownPosition({
        top: rect.bottom + window.scrollY,
        left: rect.left + window.scrollX,
        width: rect.width,
      });
    }
  }, [isOpen]);

  // Close dropdown when clicking outside
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      const target = event.target as Node;
      const clickedInside =
        wrapperRef.current?.contains(target) ||
        dropdownRef.current?.contains(target);

      if (!clickedInside) {
        setIsOpen(false);
      }
    }

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleSelect = (version: string) => {
    onVersionChange(version);
    setQuery('');
    setIsOpen(false);
  };

  // Render dropdown in portal
  const dropdownContent = isOpen && (
    <ul
      ref={dropdownRef}
      id="version-listbox"
      role="listbox"
      className="fixed z-50 mt-1 max-h-60 overflow-auto rounded-md
        bg-white py-1 shadow-lg border border-gray-200"
      style={{
        top: `${dropdownPosition.top}px`,
        left: `${dropdownPosition.left}px`,
        width: `${dropdownPosition.width}px`,
      }}
    >
      {filteredVersions.length === 0 ? (
        <li className="relative cursor-default select-none px-4 py-2 text-gray-500">
          No versions found
        </li>
      ) : (
        filteredVersions.map(version => {
          const isSelected = version === selectedVersion;
          return (
            <li
              key={version}
              role="option"
              aria-selected={isSelected}
              className={`relative cursor-pointer select-none py-2 pl-10 pr-4 hover:bg-primary-600 hover:text-white ${
                isSelected ? 'bg-primary-50' : 'text-gray-900'
              }`}
              onClick={() => handleSelect(version)}
            >
              <span
                className={`block truncate ${
                  isSelected ? 'font-medium' : 'font-normal'
                }`}
              >
                {version}
              </span>
              {isSelected && (
                <span className="absolute inset-y-0 left-0 flex items-center pl-3 text-primary-600">
                  <span
                    className="hero-check h-5 w-5"
                    aria-hidden="true"
                    role="img"
                  />
                </span>
              )}
            </li>
          );
        })
      )}
    </ul>
  );

  return (
    <div className="relative" ref={wrapperRef}>
      <div className="relative">
        <input
          ref={inputRef}
          type="text"
          className="w-full py-4.25 px-3 pr-10 border border-gray-200 rounded-md bg-white text-gray-900
            focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent"
          onChange={event => setQuery(event.target.value)}
          onFocus={() => setIsOpen(true)}
          value={isOpen ? query : selectedVersion}
          placeholder="Search versions..."
          aria-label="Version"
          role="combobox"
          aria-expanded={isOpen}
          aria-controls="version-listbox"
        />
        <button
          type="button"
          className="absolute inset-y-0 right-0 flex items-center pr-3"
          onClick={() => setIsOpen(!isOpen)}
          aria-label="Toggle version dropdown"
        >
          <span
            className="hero-chevron-down h-5 w-5 text-gray-400"
            aria-hidden="true"
            role="img"
          />
        </button>
      </div>

      {/* Render dropdown in portal to escape modal overflow */}
      {typeof document !== 'undefined' &&
        createPortal(dropdownContent, document.body)}
    </div>
  );
}
