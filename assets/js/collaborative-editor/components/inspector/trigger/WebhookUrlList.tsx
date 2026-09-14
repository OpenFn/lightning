import { useEffect, useRef } from 'react';

import { cn } from '#/utils/cn';

import type { WebhookEndpoint } from './useWebhookTrigger';

interface WebhookUrlListProps {
  /** Every URL this trigger answers on, default first. */
  endpoints: WebhookEndpoint[];
  /** Copy feedback text ('' when idle, e.g. 'Copied!' after copying). */
  copyText: string;
  /** The URL the last copy applied to, so only that row shows feedback. */
  copiedUrl: string | null;
  /** Copies the given text to the clipboard. */
  onCopy: (text: string) => void;
  /** Asks to edit the custom URL. Omit for the read-only panel. */
  onEdit?: () => void;
  /** Asks to remove the custom URL. Omit for the read-only panel. */
  onDelete?: () => void;
  /** Asks to add a custom URL. Omit for the read-only panel. */
  onAdd?: () => void;
  /** Disables the actions without hiding them. */
  disabled?: boolean;
  /**
   * When present, only the last segment of the custom URL is a field. The
   * origin and project id stay as text beside it.
   */
  editing?: {
    prefix: string;
    value: string;
    placeholder: string;
    onChange: (value: string) => void;
    /** Leave edit mode. The value is already in the draft; Finish still saves. */
    onDone: () => void;
  };
  /** Surfaced under the custom row, whether or not it is being edited. */
  customPathError?: string | null;
  /** Says the name is still being checked. Shares the error's slot. */
  checking?: boolean;
}

// The ghost variant from .claude/rules/ui-patterns.md. Every hover: needs a
// disabled:hover: to match, or a disabled button still lights up under the
// cursor.
const iconButtonClass = cn(
  'shrink-0 rounded p-1 bg-transparent text-gray-700',
  'hover:bg-gray-100 hover:text-gray-900',
  'focus-visible:outline-2 focus-visible:outline-offset-2',
  'focus-visible:outline-gray-400',
  'disabled:bg-transparent disabled:text-gray-400',
  'disabled:hover:bg-transparent disabled:hover:text-gray-400',
  'disabled:cursor-not-allowed'
);

/**
 * The URLs a webhook trigger answers on.
 *
 * Adding a name never replaces the default, so this is a list rather than one
 * field. The show panel passes no handlers and gets the read-only view.
 */
export function WebhookUrlList({
  endpoints,
  copyText,
  copiedUrl,
  onCopy,
  onEdit,
  onDelete,
  onAdd,
  disabled = false,
  editing,
  customPathError = null,
  checking = false,
}: WebhookUrlListProps) {
  const editable = Boolean(onEdit ?? onDelete ?? onAdd);
  const isEditing = Boolean(editing);
  const hasCustom = endpoints.some(endpoint => !endpoint.generated);
  const fieldRef = useRef<HTMLInputElement>(null);

  // Follows the explicit Add or Edit click. `autoFocus` would do it on mount
  // too, which is what the a11y rule is about.
  useEffect(() => {
    if (isEditing) fieldRef.current?.focus();
  }, [isEditing]);

  return (
    <div>
      <div className="block text-sm font-medium leading-6 text-slate-800">
        {endpoints.length > 1 ? 'Webhook URLs' : 'Webhook URL'}
      </div>
      <p className="block text-xs text-slate-500">
        Send a POST request to these URLs to start this event.
      </p>

      <ul
        className="mt-2 divide-y divide-gray-200 overflow-hidden rounded-lg
          border border-gray-200"
      >
        {endpoints.map(endpoint => {
          const copied = Boolean(copyText) && copiedUrl === endpoint.url;
          const usable = endpoint.usable ?? true;
          const copyLabel = !usable
            ? 'Not a usable URL yet'
            : copied
              ? copyText
              : `Copy ${endpoint.label} URL`;

          return (
            <li key={endpoint.label} className="px-2 py-2">
              <div className="flex items-center justify-between gap-2">
                <span
                  className="shrink-0 rounded-full bg-gray-50 px-2 py-0.5
                    text-[11px] font-medium leading-4 text-gray-600 ring-1
                    ring-inset ring-gray-200"
                >
                  {endpoint.label}
                </span>
                <div className="flex items-center gap-1">
                  {editable && !endpoint.generated ? (
                    <>
                      {editing ? (
                        <button
                          type="button"
                          disabled={disabled || Boolean(customPathError)}
                          onClick={editing.onDone}
                          title="Save custom URL"
                          aria-label="Save custom URL"
                          className={iconButtonClass}
                        >
                          <span className="hero-check-micro block h-4 w-4" />
                        </button>
                      ) : onEdit ? (
                        <button
                          type="button"
                          disabled={disabled}
                          onClick={onEdit}
                          title="Edit custom URL"
                          aria-label="Edit custom URL"
                          className={iconButtonClass}
                        >
                          <span className="hero-pencil-square-micro block h-4 w-4" />
                        </button>
                      ) : null}
                      {onDelete ? (
                        <button
                          type="button"
                          disabled={disabled}
                          onClick={onDelete}
                          title="Delete custom URL"
                          aria-label="Delete custom URL"
                          className={cn(
                            iconButtonClass,
                            'hover:text-red-600 disabled:hover:text-gray-400'
                          )}
                        >
                          <span className="hero-trash-micro block h-4 w-4" />
                        </button>
                      ) : null}
                    </>
                  ) : null}

                  <button
                    type="button"
                    disabled={!usable}
                    onClick={() => {
                      onCopy(endpoint.url);
                    }}
                    title={copyLabel}
                    aria-label={copyLabel}
                    className={iconButtonClass}
                  >
                    <span
                      className={`block h-4 w-4 ${
                        copied
                          ? 'hero-check-micro text-green-600'
                          : 'hero-square-2-stack-micro'
                      }`}
                    />
                  </button>
                </div>
              </div>

              {editing && !endpoint.generated ? (
                <div className="mt-0.5 break-all font-mono text-xs leading-5">
                  <span className="text-slate-400">{editing.prefix}</span>
                  <input
                    id="webhook-custom-path"
                    ref={fieldRef}
                    type="text"
                    spellCheck={false}
                    autoComplete="off"
                    aria-label="Custom path"
                    placeholder={editing.placeholder}
                    value={editing.value}
                    onChange={e => {
                      editing.onChange(e.target.value);
                    }}
                    aria-invalid={customPathError ? true : undefined}
                    aria-describedby={
                      customPathError ? 'webhook-custom-path-error' : undefined
                    }
                    style={{
                      width: `${
                        Math.max(
                          editing.value.length,
                          editing.placeholder.length
                        ) + 1
                      }ch`,
                    }}
                    onKeyDown={e => {
                      if (e.key === 'Enter') {
                        e.preventDefault();
                        if (!customPathError) editing.onDone();
                        return;
                      }

                      // Tab takes the suggestion, but only with nothing
                      // typed. With content in the field Tab has to keep
                      // moving focus.
                      if (
                        e.key === 'Tab' &&
                        !e.shiftKey &&
                        editing.value === '' &&
                        editing.placeholder !== ''
                      ) {
                        e.preventDefault();
                        editing.onChange(editing.placeholder);
                      }
                    }}
                    className={cn(
                      `border-0 bg-transparent p-0 [font-family:inherit]
                         [font-size:inherit] [font-weight:inherit]
                         [line-height:inherit] focus:outline-none
                         focus:ring-0`,
                      customPathError ? 'text-red-700' : 'text-slate-900'
                    )}
                  />
                </div>
              ) : (
                <div
                  className={cn(
                    'mt-0.5 break-all font-mono text-xs leading-5',
                    usable ? 'text-slate-600' : 'text-slate-400'
                  )}
                >
                  {endpoint.url}
                </div>
              )}

              {!endpoint.generated && (customPathError ?? checking) ? (
                <p
                  id={customPathError ? 'webhook-custom-path-error' : undefined}
                  aria-live="polite"
                  className={cn(
                    'mt-1 text-xs',
                    customPathError ? 'text-red-600' : 'text-slate-500'
                  )}
                >
                  {customPathError ?? 'Checking this name…'}
                </p>
              ) : null}
            </li>
          );
        })}
      </ul>

      {editable && !hasCustom && onAdd ? (
        <button
          type="button"
          disabled={disabled}
          onClick={onAdd}
          className={cn(
            `mt-2 flex w-full items-center justify-center gap-1.5 rounded-lg
             border border-dashed border-gray-300 bg-transparent px-3 py-2
             text-sm text-gray-700`,
            'hover:bg-gray-100 hover:text-gray-900 hover:border-gray-400',
            'focus-visible:outline-2 focus-visible:outline-offset-2',
            'focus-visible:outline-gray-400',
            'disabled:bg-transparent disabled:text-gray-400',
            'disabled:hover:bg-transparent disabled:hover:text-gray-400',
            'disabled:hover:border-gray-300 disabled:cursor-not-allowed'
          )}
        >
          <span className="hero-plus-micro h-4 w-4" />
          Add custom URL
        </button>
      ) : null}
    </div>
  );
}
