import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { cn } from '../utils/cn';

export interface Project {
  id: string;
  name: string;
}

interface ProjectPickerProps {
  'data-projects': string; // JSON-encoded array of {id, name}
  'data-current-project-id'?: string;
}

/**
 * Global Project Picker - Command palette style
 *
 * Mounted via ReactComponent hook in LiveView layouts.
 * Opens with Cmd/Ctrl+P keyboard shortcut.
 */
export function ProjectPicker(props: ProjectPickerProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [highlightedIndex, setHighlightedIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLUListElement>(null);

  // Detect macOS for keyboard shortcut display
  const isMac = useMemo(
    () =>
      typeof navigator !== 'undefined' &&
      /Mac|iPod|iPhone|iPad/.test(navigator.platform),
    []
  );

  const projects = useMemo<Project[]>(() => {
    const projectsJson = props['data-projects'];
    if (!projectsJson) return [];
    try {
      return JSON.parse(projectsJson) as Project[];
    } catch {
      return [];
    }
  }, [props['data-projects']]);

  const currentProjectId = props['data-current-project-id'];

  const filteredProjects = useMemo(() => {
    if (!searchTerm) return projects;
    const lower = searchTerm.toLowerCase();
    return projects.filter(p => p.name.toLowerCase().includes(lower));
  }, [projects, searchTerm]);

  const openPicker = useCallback(() => {
    setIsOpen(true);
    setSearchTerm('');
    // Start with first project selected (index 1), not "View all" (index 0)
    setHighlightedIndex(projects.length > 0 ? 1 : 0);
    setTimeout(() => inputRef.current?.focus(), 50);
  }, [projects.length]);

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

  // Global Escape key handler (capture phase to prevent propagation)
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

  // Keep highlighted index in bounds (0 = "View all", 1+ = projects)
  useEffect(() => {
    const maxIndex = filteredProjects.length; // 0 is "View all", so max is length not length-1
    if (highlightedIndex > maxIndex) {
      setHighlightedIndex(Math.max(0, maxIndex));
    }
  }, [filteredProjects.length, highlightedIndex]);

  // Scroll highlighted item into view
  useEffect(() => {
    if (!isOpen) return;
    const list = listRef.current;
    if (!list) return;
    // Query by data-index to avoid separator element throwing off indexing
    const highlighted = list.querySelector(
      `[data-index="${highlightedIndex}"]`
    ) as HTMLElement;
    if (highlighted) {
      highlighted.scrollIntoView({ block: 'nearest' });
    }
  }, [isOpen, highlightedIndex]);

  // Listen for custom event to open picker (from breadcrumb click)
  // Phoenix JS.dispatch sends to body
  useEffect(() => {
    const handleOpen = () => openPicker();
    document.body.addEventListener('open-project-picker', handleOpen);
    return () =>
      document.body.removeEventListener('open-project-picker', handleOpen);
  }, [openPicker]);

  // Total items = "View all projects" + filtered projects
  const totalItems = filteredProjects.length + 1;

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
            const project = filteredProjects[highlightedIndex - 1];
            if (project) {
              navigateToProject(project.id);
            }
          }
          break;
        }
      }
    },
    [filteredProjects, highlightedIndex, totalItems]
  );

  const navigateToProjectsList = () => {
    window.location.href = '/projects';
  };

  const navigateToProject = (projectId: string) => {
    window.location.href = `/projects/${projectId}/w`;
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-[9999]">
      {/* Backdrop */}
      <div className="modal-backdrop" />

      {/* Modal content - click outside closes */}
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
            {/* View all projects option */}
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
                  'hero-rectangle-stack h-5 w-5 mr-3 shrink-0',
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
            {filteredProjects.length > 0 && (
              <li className="border-t border-gray-200 my-2" role="separator" />
            )}

            {/* Project list */}
            {filteredProjects.map((project, index) => {
              const isSelected = project.id === currentProjectId;
              const itemIndex = index + 1; // +1 because 0 is "View all"
              const isHighlighted = itemIndex === highlightedIndex;

              return (
                <li
                  key={project.id}
                  data-index={itemIndex}
                  className={cn(
                    'group relative cursor-pointer select-none px-4 py-3 flex items-center',
                    isHighlighted
                      ? 'bg-primary-600 text-white'
                      : 'text-gray-900 hover:bg-primary-600 hover:text-white'
                  )}
                  role="option"
                  aria-selected={isSelected}
                  onClick={() => navigateToProject(project.id)}
                  onMouseEnter={() => setHighlightedIndex(itemIndex)}
                >
                  <span
                    className={cn(
                      'hero-folder h-5 w-5 mr-3 shrink-0',
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
                    {project.name}
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
            {filteredProjects.length === 0 && (
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
