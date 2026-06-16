import {
  Description,
  Field,
  Label,
  Listbox,
  ListboxButton,
  ListboxOption,
  ListboxOptions,
} from '@headlessui/react';

import { cn } from '#/utils/cn';

export type WebhookReply = 'before_start' | 'after_completion';

interface ResponseTypeSelectProps {
  /** The current response-type value. */
  value: WebhookReply;
  /** Called with the newly selected value. */
  onChange: (value: WebhookReply) => void;
  /** When true, the picker is read-only (matches read-only workflow gating). */
  disabled?: boolean;
}

export interface ResponseTypeOption {
  value: WebhookReply;
  label: string;
  /** Full description shown in the Configure dropdown option. */
  description: string;
  /** Trimmed variant shown on the resting panel (no parenthetical hint). */
  shortDescription: string;
}

export const IMMEDIATELY: ResponseTypeOption = {
  value: 'before_start',
  label: 'Immediately',
  description:
    'Responds immediately with a confirmation and work order ID. ' +
    '(Best for long running or queued workflows)',
  shortDescription:
    'Responds immediately with a confirmation and work order ID.',
};

export const ON_COMPLETE: ResponseTypeOption = {
  value: 'after_completion',
  label: 'On Complete',
  description: 'Responds when the workflow completes, then returns the result.',
  shortDescription:
    'Responds when the workflow completes, then returns the result.',
};

const OPTIONS: ResponseTypeOption[] = [IMMEDIATELY, ON_COMPLETE];

/**
 * Response Type picker for the webhook Configure step.
 *
 * A native `<select>` cannot render a description beneath each choice, so this
 * uses a Headless UI {@link Listbox} (mirroring {@link JobSelector}) to show the
 * rich "title + description" options from the trigger-flow Figma. Colors bridge
 * the future theme onto existing app tokens (gray borders, slate text). The
 * label is rendered here and wired to the button via `aria-labelledby` so it
 * stays a single "input with label" unit.
 */
export function ResponseTypeSelect({
  value,
  onChange,
  disabled = false,
}: ResponseTypeSelectProps) {
  const selected = OPTIONS.find(o => o.value === value) ?? IMMEDIATELY;

  return (
    <Field className="space-y-1">
      <Label className="block text-sm font-medium text-slate-800">
        Response Type
      </Label>
      <Description className="block text-xs text-slate-500">
        Set when the webhook responds on receipt, or once the workflow finishes.
      </Description>

      <Listbox value={value} onChange={onChange} disabled={disabled}>
        <div className="relative pt-1">
          <ListboxButton
            className={cn(
              'flex h-9 w-full items-center justify-between gap-2 rounded-lg',
              'border border-gray-200 bg-white px-3 text-sm text-slate-700',
              'focus:outline-none focus-visible:border-indigo-500',
              'focus-visible:ring-1 focus-visible:ring-indigo-500',
              'disabled:cursor-not-allowed disabled:opacity-50'
            )}
          >
            <span className="truncate">{selected.label}</span>
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
            {OPTIONS.map(option => (
              <ListboxOption
                key={option.value}
                value={option.value}
                className={cn(
                  'group cursor-pointer select-none rounded-md p-3',
                  'data-focus:bg-gray-50 data-focus:outline-hidden',
                  'data-selected:bg-gray-50'
                )}
              >
                <p className="text-sm font-medium text-slate-900">
                  {option.label}
                </p>
                <p className="mt-0.5 text-xs leading-5 text-slate-500">
                  {option.description}
                </p>
              </ListboxOption>
            ))}
          </ListboxOptions>
        </div>
      </Listbox>
    </Field>
  );
}
