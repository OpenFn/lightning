import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { cn } from '../utils/cn';

/**
 * Generic command-palette picker. Content-agnostic: the server ships a
 * pre-flattened list of items plus display strings, and this component
 * renders the modal, handles search, keyboard navigation, and navigation.
 *
 * Used by the project picker today. The same component will back a billing
 * account picker (and any future context-scoped picker) — the only thing
 * that changes is which data the layout feeds in.
 */

export interface PickerItem {
  id: string;
  /** The leaf label shown on the row (e.g. project name). */
  label: string;
  /** Full path used for search matching (e.g. "parent/child/leaf"). */
  searchLabel: string;
  /** Indent level; 0 for top-level items. */
  depth: number;
  /** Optional accent color (sandboxes, account tiers). */
  color?: string | null;
  /** Where to navigate when selected. Pre-computed server-side. */
  href: string;
  /**
   * True when `href` targets the same section as the current URL. The
   * picker uses this to decide whether to preserve the current URL's hash
   * when navigating — it's only meaningful on same-section switches.
   */
  sameSection?: boolean;
  /**
   * Optional hero icon class for the row (e.g. `hero-credit-card`).
   * When absent, falls back to the project-style default:
   * `hero-folder` at depth 0 and `hero-beaker` for nested items.
   */
  icon?: string;
}

interface PickerProps {
  'data-items': string;
  'data-current-id'?: string;
  'data-placeholder': string;
  'data-empty-message': string;
  'data-view-all-label': string;
  'data-view-all-href': string;
  /**
   * Event name the picker listens for on `document.body` to open.
   * The matching trigger button dispatches this event.
   */
  'data-open-event': string;
  /**
   * Optional theme class name; passed through the layout's
   * `@side_menu_theme` so the picker's accent color follows scope.
   * Valid values today: `"primary-theme"`, `"secondary-variant"`,
   * `"sudo-variant"`.
   */
  'data-theme'?: string;
}

export function Picker(props: PickerProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [highlightedIndex, setHighlightedIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLUListElement>(null);

  const isMac = useMemo(
    () =>
      typeof navigator !== 'undefined' &&
      /Mac|iPod|iPhone|iPad/.test(navigator.platform),
    []
  );

  const allItems = useMemo<PickerItem[]>(() => {
    const json = props['data-items'];
    if (!json) return [];
    try {
      return JSON.parse(json) as PickerItem[];
    } catch {
      return [];
    }
  }, [props['data-items']]);

  const currentId = props['data-current-id'];
  const placeholder = props['data-placeholder'];
  const emptyMessage = props['data-empty-message'];
  const viewAllLabel = props['data-view-all-label'];
  const viewAllHref = props['data-view-all-href'];
  const openEvent = props['data-open-event'];
  const theme = props['data-theme'] ?? '';

  // Filter items by search term. Items are already tree-flattened server-side;
  // we only need to include matches *and* the ancestors that lead to them so
  // the indentation still reads correctly.
  const items = useMemo<PickerItem[]>(() => {
    if (!searchTerm) return allItems;
    const lower = searchTerm.toLowerCase();

    // Mark matches and include ancestor chain for each match.
    const selfMatch = allItems.map(i =>
      i.searchLabel.toLowerCase().includes(lower)
    );
    const include = new Array<boolean>(allItems.length).fill(false);

    for (let i = 0; i < allItems.length; i++) {
      if (!selfMatch[i]) continue;
      include[i] = true;
      // Walk backwards from this item, marking each shallower ancestor as
      // needed. Server gives us items in pre-order, so the parent is the
      // most recent item with a strictly smaller depth.
      let depth = allItems[i]!.depth;
      for (let j = i - 1; j >= 0 && depth > 0; j--) {
        const candidate = allItems[j]!;
        if (candidate.depth < depth) {
          include[j] = true;
          depth = candidate.depth;
        }
      }
    }

    return allItems.filter((_, i) => include[i]);
  }, [allItems, searchTerm]);

  // "View all" is always index 0; items start at index 1.
  const totalItems = items.length + 1;

  const openPicker = useCallback(() => {
    setIsOpen(true);
    setSearchTerm('');
    setHighlightedIndex(items.length > 0 ? 1 : 0);
  }, [items.length]);

  useEffect(() => {
    if (isOpen) {
      setTimeout(() => inputRef.current?.focus(), 50);
    }
  }, [isOpen]);

  const closePicker = useCallback(() => {
    setIsOpen(false);
  }, []);

  // Cmd/Ctrl+P to toggle.
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'p') {
        e.preventDefault();
        if (isOpen) {
          closePicker();
        } else {
          openPicker();
        }
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, openPicker, closePicker]);

  // Escape to close (capture phase so we beat nested handlers).
  useEffect(() => {
    if (!isOpen) return;

    const handleGlobalKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
        closePicker();
      }
    };

    document.addEventListener('keydown', handleGlobalKeyDown, true);
    return () =>
      document.removeEventListener('keydown', handleGlobalKeyDown, true);
  }, [isOpen, closePicker]);

  useEffect(() => {
    if (highlightedIndex >= totalItems) {
      setHighlightedIndex(Math.max(0, totalItems - 1));
    }
  }, [totalItems, highlightedIndex]);

  useEffect(() => {
    if (!isOpen) return;
    const list = listRef.current;
    if (!list) return;
    const highlighted = list.querySelector(
      `[data-index="${highlightedIndex}"]`
    ) as HTMLElement;
    if (highlighted) {
      highlighted.scrollIntoView({ block: 'nearest' });
    }
  }, [isOpen, highlightedIndex]);

  // Listen for the configured open event (dispatched by the trigger button).
  useEffect(() => {
    const handleOpen = () => openPicker();
    document.body.addEventListener(openEvent, handleOpen);
    return () => document.body.removeEventListener(openEvent, handleOpen);
  }, [openPicker, openEvent]);

  const go = (href: string, sameSection = false) => {
    window.location.href = href + (sameSection ? window.location.hash : '');
  };

  const handleInputKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      switch (e.key) {
        case 'ArrowDown':
          e.preventDefault();
          setHighlightedIndex(i => (i < totalItems - 1 ? i + 1 : 0));
          break;
        case 'ArrowUp':
          e.preventDefault();
          setHighlightedIndex(i => (i > 0 ? i - 1 : totalItems - 1));
          break;
        case 'Enter': {
          e.preventDefault();
          if (highlightedIndex === 0) {
            go(viewAllHref);
          } else {
            const item = items[highlightedIndex - 1];
            if (item) go(item.href, item.sameSection);
          }
          break;
        }
      }
    },
    [items, highlightedIndex, totalItems, viewAllHref]
  );

  if (!isOpen) return null;

  return (
    <div className={cn('picker-root fixed inset-0 z-[9999]', theme)}>
      <div className="modal-backdrop" />

      <div
        className="fixed inset-0 flex items-start justify-center pt-[15vh]"
        onClick={closePicker}
      >
        <div
          className="w-full max-w-xl bg-white rounded-xl shadow-2xl ring-1 ring-black/10 overflow-hidden"
          onClick={e => e.stopPropagation()}
        >
          <div className="flex items-center px-4 border-b border-gray-200">
            <span className="hero-magnifying-glass h-5 w-5 text-gray-400 shrink-0" />
            <input
              ref={inputRef}
              type="text"
              spellCheck="false"
              autoComplete="off"
              placeholder={placeholder}
              value={searchTerm}
              onChange={e => setSearchTerm(e.target.value)}
              onKeyDown={handleInputKeyDown}
              className="w-full border-0 py-4 pl-3 pr-4 text-gray-900 placeholder:text-gray-400 focus:ring-0 text-base"
              role="combobox"
              aria-controls="picker-options"
              aria-expanded="true"
            />
            <kbd className="hidden sm:inline-flex items-center gap-1 rounded px-2 py-1 text-xs text-gray-400 ring-1 ring-gray-300">
              <span>{isMac ? '⌘' : 'Ctrl'}</span>
              <span>P</span>
            </kbd>
          </div>

          <ul
            ref={listRef}
            className="max-h-80 overflow-y-auto py-2"
            id="picker-options"
            role="listbox"
          >
            <li
              data-index={0}
              className={cn(
                'group relative cursor-pointer select-none px-4 py-3 flex items-center',
                highlightedIndex === 0
                  ? 'bg-primary-600 text-white'
                  : 'text-gray-900 hover:bg-primary-600 hover:text-white'
              )}
              role="option"
              onClick={() => go(viewAllHref)}
              onMouseEnter={() => setHighlightedIndex(0)}
            >
              <span
                className={cn(
                  'hero-rectangle-stack h-5 w-5 mr-2 shrink-0',
                  highlightedIndex === 0
                    ? 'text-white/70'
                    : 'text-gray-400 group-hover:text-white/70'
                )}
              />
              <span className="flex-grow">{viewAllLabel}</span>
              <span
                className={cn(
                  'hero-arrow-right h-4 w-4 shrink-0',
                  highlightedIndex === 0
                    ? 'text-white/70'
                    : 'text-gray-400 group-hover:text-white/70'
                )}
              />
            </li>

            {items.length > 0 && (
              <li className="border-t border-gray-200 my-2" role="separator" />
            )}

            {items.map((item, index) => {
              const itemIndex = index + 1;
              const isHighlighted = itemIndex === highlightedIndex;
              const isSelected = item.id === currentId;
              const isNested = item.depth > 0;
              const indentPx = item.depth * 10;
              const itemIcon =
                item.icon ?? (isNested ? 'hero-beaker' : 'hero-folder');

              return (
                <li
                  key={item.id}
                  data-index={itemIndex}
                  className={cn(
                    'group relative cursor-pointer select-none py-3 pr-4 flex items-center',
                    isHighlighted
                      ? 'bg-primary-600 text-white'
                      : 'text-gray-900 hover:bg-primary-600 hover:text-white'
                  )}
                  style={{ paddingLeft: `${16 + indentPx}px` }}
                  role="option"
                  aria-selected={isSelected}
                  onClick={() => go(item.href, item.sameSection)}
                  onMouseEnter={() => setHighlightedIndex(itemIndex)}
                >
                  {isNested && (
                    <span
                      className={cn(
                        'hero-arrow-turn-down-right h-4 w-4 mr-2 shrink-0',
                        isHighlighted
                          ? 'text-white/50'
                          : 'text-gray-300 group-hover:text-white/50'
                      )}
                    />
                  )}
                  <span
                    className={cn(
                      `${itemIcon} h-5 w-5 mr-2 shrink-0`,
                      isHighlighted
                        ? 'text-white/70'
                        : 'text-gray-400 group-hover:text-white/70'
                    )}
                  />
                  <span
                    className={cn(
                      'truncate flex-grow',
                      isSelected && 'font-semibold'
                    )}
                  >
                    {item.label}
                  </span>
                  {isSelected && (
                    <span
                      className={cn(
                        'hero-check shrink-0 ml-3 w-5 h-5',
                        isHighlighted
                          ? 'text-white'
                          : 'text-primary-600 group-hover:text-white'
                      )}
                    />
                  )}
                </li>
              );
            })}
            {items.length === 0 && (
              <li className="px-4 py-8 text-center text-gray-500">
                {emptyMessage}
              </li>
            )}
          </ul>
        </div>
      </div>
    </div>
  );
}
