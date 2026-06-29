import type { Meta, StoryObj } from '@storybook/react-vite';
import { useId, useState } from 'react';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clones of the form primitives in
 * `LightningWeb.Components.NewInputs` (lib/lightning_web/components/new_inputs.ex):
 * `label/1`, `error/1`, `input_element/1`, `textarea_element/1`,
 * `checkbox_element/1` and the `type="toggle"` switch.
 *
 * Inputs are uncontrolled (defaultValue/defaultChecked) since these are visual
 * specimens, not wired-up form fields.
 */
const INPUT_BASE =
  'focus:outline focus:outline-2 focus:outline-offset-1 block w-full rounded-lg text-slate-900 focus:ring-0 sm:text-sm sm:leading-6 disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500';
const INPUT_OK =
  'border-slate-300 focus:border-slate-400 focus:outline-primary-600';
const INPUT_ERR =
  'border-danger-400 focus:border-danger-400 focus:outline-danger-400';

function Label({
  htmlFor,
  children,
}: {
  htmlFor: string;
  children: ReactNode;
}) {
  return (
    <label htmlFor={htmlFor} className="text-sm/6 font-medium text-slate-800">
      {children}
    </label>
  );
}

function ErrorMessage({ children }: { children: ReactNode }) {
  return (
    <p
      data-tag="error_message"
      className="mt-1 inline-flex items-center gap-x-1.5 text-xs text-danger-600"
    >
      <span className="hero-exclamation-circle h-4 w-4" />
      {children}
    </p>
  );
}

interface TextFieldProps {
  label: string;
  sublabel?: string;
  placeholder?: string;
  defaultValue?: string;
  error?: string;
  disabled?: boolean;
}

function TextField({
  label,
  sublabel,
  placeholder,
  defaultValue,
  error,
  disabled,
}: TextFieldProps) {
  const id = useId();
  return (
    <div>
      <div className="mb-2">
        <Label htmlFor={id}>{label}</Label>
      </div>
      {sublabel ? (
        <small className="mb-2 block text-xs text-gray-600">{sublabel}</small>
      ) : null}
      <input
        id={id}
        type="text"
        defaultValue={defaultValue}
        placeholder={placeholder}
        disabled={disabled}
        className={cn(INPUT_BASE, error ? INPUT_ERR : INPUT_OK)}
      />
      {error ? <ErrorMessage>{error}</ErrorMessage> : null}
    </div>
  );
}

function SelectField({ label }: { label: string }) {
  const id = useId();
  return (
    <div>
      <div className="mb-2">
        <Label htmlFor={id}>{label}</Label>
      </div>
      <select id={id} className={cn(INPUT_BASE, INPUT_OK)} defaultValue="always">
        <option value="always">Always</option>
        <option value="on_success">On success</option>
        <option value="on_failure">On failure</option>
      </select>
    </div>
  );
}

function TextareaField({ label }: { label: string }) {
  const id = useId();
  return (
    <div>
      <div className="mb-2">
        <Label htmlFor={id}>{label}</Label>
      </div>
      <textarea
        id={id}
        rows={3}
        defaultValue={'fn(state => {\n  return state;\n})'}
        className={cn(
          'focus:outline focus:outline-2 focus:outline-offset-1 block w-full overflow-y-auto rounded-md text-sm shadow-xs focus:ring-0 sm:text-sm sm:leading-6',
          INPUT_OK
        )}
      />
    </div>
  );
}

function CheckboxField({
  label,
  defaultChecked,
}: {
  label: string;
  defaultChecked?: boolean;
}) {
  const id = useId();
  return (
    <div className="flex items-center gap-2">
      <input
        id={id}
        type="checkbox"
        defaultChecked={defaultChecked}
        className="cursor-pointer rounded border-gray-300 text-primary-600 transition duration-200 checked:border-primary-600 checked:bg-primary-600 focus:ring-primary-600 focus:outline-none"
      />
      <Label htmlFor={id}>{label}</Label>
    </div>
  );
}

function Toggle({
  label,
  defaultOn,
}: {
  label: string;
  defaultOn?: boolean;
}) {
  const [on, setOn] = useState(defaultOn ?? false);
  return (
    <label className="relative inline-flex cursor-pointer items-center">
      <button
        type="button"
        role="switch"
        aria-checked={on}
        aria-label={label}
        onClick={() => {
          setOn(value => !value);
        }}
        className={cn(
          'relative inline-flex h-6 w-11 rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out',
          'focus:ring-2 focus:ring-primary-500 focus:ring-offset-2 focus:outline-none',
          on ? 'bg-primary-600' : 'bg-gray-200'
        )}
      >
        <span
          className={cn(
            'pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out',
            on ? 'translate-x-5' : 'translate-x-0'
          )}
        >
          <span
            className={cn(
              'absolute inset-0 flex h-full w-full items-center justify-center transition-opacity',
              on ? 'opacity-0' : 'opacity-100'
            )}
            aria-hidden="true"
          >
            <span className="hero-x-mark-micro h-4 w-4 text-gray-400" />
          </span>
          <span
            className={cn(
              'absolute inset-0 flex h-full w-full items-center justify-center transition-opacity',
              on ? 'opacity-100' : 'opacity-0'
            )}
            aria-hidden="true"
          >
            <span className="hero-check-micro h-4 w-4 text-primary-600" />
          </span>
        </span>
      </button>
      <span className="ml-3 text-sm font-medium text-gray-900 select-none">
        {label}
      </span>
    </label>
  );
}

const meta = {
  title: 'LiveView Clones/Form Inputs (LiveView Clone)',
  tags: ['core'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Inputs: Story = {
  render: () => (
    <Showcase className="max-w-md">
      <Section title="Text inputs">
        <div className="flex flex-col gap-5">
          <TextField
            label="Workflow name"
            placeholder="My workflow"
            defaultValue="Patient sync"
          />
          <TextField
            label="Webhook URL"
            sublabel="Requests to this URL trigger the workflow."
            defaultValue="https://app.openfn.org/i/abc"
          />
          <TextField
            label="Project name"
            defaultValue="bad name!"
            error="has invalid format"
          />
          <TextField
            label="Read-only field"
            defaultValue="locked"
            disabled
          />
        </div>
      </Section>

      <Section title="Select, textarea & checkbox">
        <div className="flex flex-col gap-5">
          <SelectField label="Run condition" />
          <TextareaField label="Body" />
          <CheckboxField label="Enabled" defaultChecked />
          <CheckboxField label="Send notifications" />
        </div>
      </Section>

      <Section
        title="Toggle"
        description="The type=&quot;toggle&quot; switch. Click to flip."
      >
        <div className="flex flex-col gap-3">
          <Toggle label="Trigger enabled" defaultOn />
          <Toggle label="Beta features" />
        </div>
      </Section>
    </Showcase>
  ),
};
