import {
  Listbox,
  ListboxButton,
  ListboxOption,
  ListboxOptions,
} from '@headlessui/react';
import { useEffect, useRef, useState } from 'react';

import { cn } from '#/utils/cn';

import type { WebhookAuthMethod } from '../../../types/sessionContext';

interface WebhookAuthMethodSelectProps {
  /** All webhook auth methods available in the project. */
  methods: WebhookAuthMethod[];
  /** Currently selected auth-method ids (buffered in the draft). */
  selectedIds: string[];
  /** Called with the new id set when the selection changes. */
  onChange: (ids: string[]) => void;
  /** Opens the create-a-new-auth-method flow. */
  onCreateNew: () => void;
  /** Whether the user may create new auth methods. */
  canCreate: boolean;
}

/** A row may be unfilled (null) while the user is still picking a method. */
type Row = string | null;

function authTypeLabel(method: WebhookAuthMethod): string {
  return method.auth_type === 'api' ? 'API Key' : 'Basic Auth';
}

/** Order-independent comparison of two id sets. */
function sameIdSet(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const setB = new Set(b);
  return a.every(id => setB.has(id));
}

/**
 * Credential picker for the webhook Configure step's Authentication section
 * (Figma 1.2.2). Renders one row per attached auth method; each row is a
 * single-select dropdown of the project's methods. "Add" appends an empty row
 * so more than one method can be attached, and a "Create a new authentication
 * method" link at the bottom opens the create flow.
 *
 * Rows are local state — selecting a method emits the non-empty id set via
 * `onChange`, which is buffered into the draft and only persisted on Finish.
 */
export function WebhookAuthMethodSelect({
  methods,
  selectedIds,
  onChange,
  onCreateNew,
  canCreate,
}: WebhookAuthMethodSelectProps) {
  // Seed one row per existing association, or a single empty row to pick into.
  const [rows, setRows] = useState<Row[]>(() =>
    selectedIds.length > 0 ? [...selectedIds] : [null]
  );

  // `selectedIds` is seeded from the draft, which itself often resolves only
  // after the project's auth methods load asynchronously. Until the user edits
  // the rows we keep mirroring that incoming set; once they touch the selection
  // their edit owns the rows and later async updates no longer clobber it.
  const touchedRef = useRef(false);

  useEffect(() => {
    if (touchedRef.current) return;
    setRows(current => {
      const currentIds = current.filter((id): id is string => id !== null);
      if (sameIdSet(currentIds, selectedIds)) return current;
      return selectedIds.length > 0 ? [...selectedIds] : [null];
    });
  }, [selectedIds]);

  const commit = (next: Row[]) => {
    touchedRef.current = true;
    setRows(next);
    onChange(next.filter((id): id is string => id !== null));
  };

  const setRow = (index: number, id: string) => {
    const next = [...rows];
    next[index] = id;
    commit(next);
  };

  const removeRow = (index: number) => {
    const next = rows.filter((_, i) => i !== index);
    // Always leave at least one (empty) picker visible.
    commit(next.length > 0 ? next : [null]);
  };

  const addRow = () => {
    touchedRef.current = true;
    setRows(prev => [...prev, null]);
  };

  const hasEmptyRow = rows.includes(null);
  const allAttached = rows.filter(Boolean).length >= methods.length;
  const canAddRow = methods.length > 0 && !hasEmptyRow && !allAttached;

  // No methods exist in the project at all.
  if (methods.length === 0) {
    return (
      <div className="rounded-lg border border-dashed border-gray-200 p-4 text-center">
        <p className="text-sm text-slate-500">
          No authentication methods exist in this project yet.
        </p>
        {canCreate && (
          <button
            type="button"
            onClick={onCreateNew}
            className="link mt-1 text-sm font-medium"
          >
            Create a new authentication method
          </button>
        )}
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {rows.map((rowId, index) => {
        // Hide methods already chosen in other rows to prevent duplicates.
        const usedElsewhere = new Set(
          rows.filter((id, i): id is string => i !== index && id !== null)
        );
        const available = methods.filter(m => !usedElsewhere.has(m.id));
        const selected = rowId ? methods.find(m => m.id === rowId) : undefined;

        return (
          <div
            key={`${rowId ?? 'empty'}-${index}`}
            className="flex items-center gap-2"
          >
            <Listbox value={rowId} onChange={id => setRow(index, id as string)}>
              <div className="relative flex-1">
                <ListboxButton
                  aria-label={`Authentication credential ${index + 1}`}
                  className={cn(
                    'flex h-9 w-full items-center justify-between gap-2 rounded-lg',
                    'border border-gray-200 bg-white px-3 text-sm',
                    'focus:outline-none focus-visible:border-indigo-500',
                    'focus-visible:ring-1 focus-visible:ring-indigo-500',
                    selected ? 'text-slate-700' : 'text-slate-400'
                  )}
                >
                  <span className="truncate">
                    {selected ? selected.name : 'Select a credential'}
                  </span>
                  <span className="hero-chevron-down-mini h-4 w-4 shrink-0 text-slate-400" />
                </ListboxButton>

                <ListboxOptions
                  transition
                  anchor="bottom start"
                  className={cn(
                    'z-[100] mt-1 w-[var(--button-width)] overflow-auto rounded-lg',
                    'bg-white p-1 shadow-lg outline-1 outline-black/5',
                    'data-leave:transition data-leave:duration-100 data-leave:ease-in',
                    'data-closed:data-leave:opacity-0'
                  )}
                >
                  {available.map(method => (
                    <ListboxOption
                      key={method.id}
                      value={method.id}
                      className={cn(
                        'group flex cursor-pointer select-none items-center gap-2',
                        'rounded-md p-2 text-sm',
                        'data-focus:bg-gray-50 data-focus:outline-hidden'
                      )}
                    >
                      <span className="hero-check-mini h-4 w-4 shrink-0 text-indigo-600 opacity-0 group-data-selected:opacity-100" />
                      <span className="min-w-0 flex-1">
                        <span className="block truncate font-medium text-slate-900">
                          {method.name}
                        </span>
                        <span className="block text-xs text-slate-500">
                          {authTypeLabel(method)}
                        </span>
                      </span>
                    </ListboxOption>
                  ))}
                </ListboxOptions>
              </div>
            </Listbox>

            <button
              type="button"
              onClick={() => removeRow(index)}
              aria-label={`Remove credential ${index + 1}`}
              className={cn(
                'flex h-9 w-9 shrink-0 items-center justify-center rounded-lg',
                'text-slate-400 hover:bg-gray-100 hover:text-slate-600',
                'focus:outline-none focus-visible:ring-1 focus-visible:ring-indigo-500'
              )}
            >
              <span className="hero-trash-mini h-4 w-4" />
            </button>
          </div>
        );
      })}

      <div className="flex items-center justify-between pt-1">
        <button
          type="button"
          onClick={addRow}
          disabled={!canAddRow}
          className={cn(
            'inline-flex items-center gap-1 text-sm font-medium',
            'text-indigo-600 hover:text-indigo-700',
            'disabled:cursor-not-allowed disabled:text-slate-300'
          )}
        >
          <span className="hero-plus-micro h-4 w-4" />
          Add
        </button>

        {canCreate && (
          <button
            type="button"
            onClick={onCreateNew}
            className="link text-sm font-medium"
          >
            Create a new authentication method
          </button>
        )}
      </div>
    </div>
  );
}
