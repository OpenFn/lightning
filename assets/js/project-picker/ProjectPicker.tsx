import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { cn } from '../utils/cn';

export interface Project {
  id: string;
  name: string;
  color?: string | null;
  parent_id?: string | null;
}

/** Flattened item for keyboard navigation and rendering. */
interface PickerItem {
  type: 'project' | 'sandbox';
  id: string;
  /** Display label — just the project's own name. */
  label: string;
  /** Full path (parent:child:...) used for search matching. */
  searchLabel: string;
  depth: number;
  color?: string | null | undefined;
}

interface ProjectPickerProps {
  'data-projects': string;
  'data-current-project-id'?: string;
}

/**
 * Global Project Picker - Command palette style
 *
 * Mounted via ReactComponent hook in LiveView layouts.
 * Opens with Cmd/Ctrl+P keyboard shortcut.
 *
 * Projects are listed at the top level. Sandboxes belonging to each project
 * are nested underneath their parent as indented children.
 */
export function ProjectPicker(props: ProjectPickerProps) {
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

  const projects = useMemo<Project[]>(() => {
    const json = props['data-projects'];
    if (!json) return [];
    try {
      return JSON.parse(json) as Project[];
    } catch {
      return [];
    }
  }, [props['data-projects']]);

  const currentProjectId = props['data-current-project-id'];

  /**
   * Build a display label for a project by walking up the parent chain.
   * e.g. "root:child:grandchild"
   */
  const buildLabel = useCallback(
    (project: Project, projectMap: Map<string, Project>): string => {
      const parts: string[] = [project.name];
      let current = project;
      while (current.parent_id) {
        const parent = projectMap.get(current.parent_id);
        if (!parent) break;
        parts.unshift(parent.name);
        current = parent;
      }
      return parts.join('/');
    },
    []
  );

  /**
   * Build a flat list of picker items from the project tree,
   * filtered by search term. Children are nested after their parent.
   */
  const items = useMemo<PickerItem[]>(() => {
    const lower = searchTerm.toLowerCase();
    const projectMap = new Map(projects.map(p => [p.id, p]));

    // Group children by parent_id
    const childrenOf = new Map<string | null, Project[]>();
    for (const p of projects) {
      const parentId = p.parent_id ?? null;
      if (!childrenOf.has(parentId)) {
        childrenOf.set(parentId, []);
      }
      childrenOf.get(parentId)!.push(p);
    }

    const result: PickerItem[] = [];

    // Recursively build the tree in display order
    const walk = (parentId: string | null, depth: number) => {
      const children = childrenOf.get(parentId) || [];
      for (const project of children) {
        const searchLabel = buildLabel(project, projectMap);
        const isSandbox = project.parent_id != null;
        const matches =
          !searchTerm || searchLabel.toLowerCase().includes(lower);

        // Check if any descendant matches
        const hasMatchingDescendant = (id: string): boolean => {
          const desc = childrenOf.get(id) || [];
          return desc.some(
            d =>
              buildLabel(d, projectMap).toLowerCase().includes(lower) ||
              hasMatchingDescendant(d.id)
          );
        };

        if (matches || hasMatchingDescendant(project.id)) {
          result.push({
            type: isSandbox ? 'sandbox' : 'project',
            id: project.id,
            label: project.name,
            searchLabel,
            depth,
            color: project.color,
          });
          walk(project.id, depth + 1);
        }
      }
    };

    walk(null, 0);
    return result;
  }, [projects, searchTerm, buildLabel]);

  // "View all" is always index 0; items start at index 1
  const totalItems = items.length + 1;

  const openPicker = useCallback(() => {
    setIsOpen(true);
    setSearchTerm('');
    setHighlightedIndex(items.length > 0 ? 1 : 0);
  }, [items.length]);

  // Focus input after open (separate effect to avoid stale ref)
  useEffect(() => {
    if (isOpen) {
      setTimeout(() => inputRef.current?.focus(), 50);
    }
  }, [isOpen]);

  const closePicker = useCallback(() => {
    setIsOpen(false);
  }, []);

  // Keyboard shortcut: Cmd/Ctrl+P to open
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

  // Global Escape key handler (capture phase)
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

  // Keep highlighted index in bounds
  useEffect(() => {
    if (highlightedIndex >= totalItems) {
      setHighlightedIndex(Math.max(0, totalItems - 1));
    }
  }, [totalItems, highlightedIndex]);

  // Scroll highlighted item into view
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

  // Listen for custom event from breadcrumb click
  useEffect(() => {
    const handleOpen = () => openPicker();
    document.body.addEventListener('open-project-picker', handleOpen);
    return () =>
      document.body.removeEventListener('open-project-picker', handleOpen);
  }, [openPicker]);

  const navigateToProjectsList = () => {
    window.location.href = '/projects';
  };

  const navigateToProject = (projectId: string) => {
    const match = window.location.pathname.match(/^\/projects\/[^/]+\/(.*)/);
    let rest = match?.[1] || 'w';

    // Workflow paths contain project-specific IDs — keep only the section
    if (rest.startsWith('w/')) {
      rest = 'w';
    }

    window.location.href = `/projects/${projectId}/${rest}${window.location.search}${window.location.hash}`;
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
            navigateToProjectsList();
          } else {
            const item = items[highlightedIndex - 1];
            if (item) {
              navigateToProject(item.id);
            }
          }
          break;
        }
      }
    },
    [items, highlightedIndex, totalItems]
  );

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-[9999]">
      {/* Backdrop */}
      <div className="modal-backdrop" />

      {/* Modal content */}
      <div
        className="fixed inset-0 flex items-start justify-center pt-[15vh]"
        onClick={closePicker}
      >
        <div
          className="w-full max-w-xl bg-white rounded-xl shadow-2xl ring-1 ring-black/10 overflow-hidden"
          onClick={e => e.stopPropagation()}
        >
          {/* Search input */}
          <div className="flex items-center px-4 border-b border-gray-200">
            <span className="hero-magnifying-glass h-5 w-5 text-gray-400 shrink-0" />
            <input
              ref={inputRef}
              type="text"
              spellCheck="false"
              placeholder="Search projects..."
              value={searchTerm}
              onChange={e => setSearchTerm(e.target.value)}
              onKeyDown={handleInputKeyDown}
              className="w-full border-0 py-4 pl-3 pr-4 text-gray-900 placeholder:text-gray-400 focus:ring-0 text-base"
              role="combobox"
              aria-controls="project-picker-options"
              aria-expanded="true"
              autoComplete="off"
            />
            <kbd className="hidden sm:inline-flex items-center gap-1 rounded px-2 py-1 text-xs text-gray-400 ring-1 ring-gray-300">
              <span>{isMac ? '⌘' : 'Ctrl'}</span>
              <span>P</span>
            </kbd>
          </div>

          {/* Options list */}
          <ul
            ref={listRef}
            className="max-h-80 overflow-y-auto py-2"
            id="project-picker-options"
            role="listbox"
          >
            {/* View all projects */}
            <li
              data-index={0}
              className={cn(
                'group relative cursor-pointer select-none px-4 py-3 flex items-center',
                highlightedIndex === 0
                  ? 'bg-primary-600 text-white'
                  : 'text-gray-900 hover:bg-primary-600 hover:text-white'
              )}
              role="option"
              onClick={navigateToProjectsList}
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
              <span className="flex-grow">View all projects</span>
              <span
                className={cn(
                  'hero-arrow-right h-4 w-4 shrink-0',
                  highlightedIndex === 0
                    ? 'text-white/70'
                    : 'text-gray-400 group-hover:text-white/70'
                )}
              />
            </li>

            {/* Separator */}
            {items.length > 0 && (
              <li className="border-t border-gray-200 my-2" role="separator" />
            )}

            {/* Project and sandbox list */}
            {items.map((item, index) => {
              const itemIndex = index + 1;
              const isHighlighted = itemIndex === highlightedIndex;
              const isSelected = item.id === currentProjectId;
              const isSandbox = item.depth > 0;
              const indentPx = item.depth * 10;

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
                  onClick={() => navigateToProject(item.id)}
                  onMouseEnter={() => setHighlightedIndex(itemIndex)}
                >
                  {isSandbox ? (
                    <>
                      <span
                        className={cn(
                          'hero-arrow-turn-down-right h-4 w-4 mr-2 shrink-0',
                          isHighlighted
                            ? 'text-white/50'
                            : 'text-gray-300 group-hover:text-white/50'
                        )}
                      />
                      <span
                        className={cn(
                          'hero-beaker h-5 w-5 mr-2 shrink-0',
                          isHighlighted
                            ? 'text-white/70'
                            : 'text-gray-400 group-hover:text-white/70'
                        )}
                      />
                    </>
                  ) : (
                    <span
                      className={cn(
                        'hero-folder h-5 w-5 mr-2 shrink-0',
                        isHighlighted
                          ? 'text-white/70'
                          : 'text-gray-400 group-hover:text-white/70'
                      )}
                    />
                  )}
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
                No projects found
              </li>
            )}
          </ul>
        </div>
      </div>
    </div>
  );
}
