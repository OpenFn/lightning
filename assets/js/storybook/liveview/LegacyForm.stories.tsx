import type { Meta, StoryObj } from '@storybook/react-vite';
import { useId } from 'react';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clones of the legacy form primitives in
 * `LightningWeb.Components.Form` (lib/lightning_web/live/components/form.ex):
 * `submit_button/1`, `text_area/1`, `password_field/1`, `email_field/1`,
 * `text_field/1`, `check_box/1`, `label_field/1`, `select_field/1`, `select/1`
 * and `divider/1`.
 *
 * These wrap `PhoenixHTMLHelpers.Form` helpers in the server; here the inputs
 * are uncontrolled (defaultValue/defaultChecked) presentational specimens with
 * no `phx-*` bindings or error plumbing.
 */

const LABEL_CLASSES = 'block text-sm font-medium text-secondary-700';

const TEXT_FIELD_INPUT_CLASSES =
  'block w-full rounded-md border-0 py-1.5 text-gray-900 shadow-xs ring-1 ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-indigo-600 disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500 disabled:ring-gray-200 sm:text-sm sm:leading-6';

const PASSWORD_INPUT_CLASSES =
  'mt-1 focus:ring-primary-500 focus:border-primary-500 block w-full shadow-xs sm:text-sm border-secondary-300 rounded-md';

const SELECT_FIELD_CLASSES =
  'mt-1 block w-full rounded-md border-secondary-300 shadow-xs sm:text-sm focus:border-primary-300 focus:ring focus:ring-primary-200/50 disabled:cursor-not-allowed';

const SELECT_CLASSES =
  'block w-full rounded-md border-secondary-300 sm:text-sm shadow-xs focus:border-primary-300 focus:ring focus:ring-primary-200/50 disabled:cursor-not-allowed';

// submit_button/1
function SubmitButton({
  children,
  disabled,
}: {
  children: ReactNode;
  disabled?: boolean;
}) {
  return (
    <button
      type="submit"
      disabled={disabled}
      className="inline-flex justify-center py-2 px-4 border border-transparent shadow-xs text-sm font-medium rounded-md text-white focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500 enabled:bg-primary-600 enabled:hover:bg-primary-700 disabled:bg-primary-300"
    >
      {children}
    </button>
  );
}

// text_area/1
function TextArea({
  label,
  defaultValue,
}: {
  label: string;
  defaultValue?: string;
}) {
  const id = useId();
  return (
    <div>
      <div className="flex">
        <div className="shrink">
          <label htmlFor={id} className={LABEL_CLASSES}>
            {label}
          </label>
        </div>
        <div className="grow text-right" />
      </div>
      <textarea
        id={id}
        defaultValue={defaultValue}
        className="rounded-md w-full font-mono bg-slate-800 text-slate-50 h-96"
      />
    </div>
  );
}

// password_field/1
function PasswordField({
  label,
  defaultValue,
  required,
}: {
  label: string;
  defaultValue?: string;
  required?: boolean;
}) {
  const id = useId();
  return (
    <div>
      <label htmlFor={id} className={LABEL_CLASSES}>
        {label}
      </label>
      <input
        id={id}
        type="password"
        autoComplete="off"
        required={required}
        defaultValue={defaultValue}
        className={PASSWORD_INPUT_CLASSES}
      />
    </div>
  );
}

// email_field/1
function EmailField({
  label,
  defaultValue,
  required,
}: {
  label: string;
  defaultValue?: string;
  required?: boolean;
}) {
  const id = useId();
  return (
    <div>
      <label htmlFor={id} className={LABEL_CLASSES}>
        {label}
      </label>
      <input
        id={id}
        type="email"
        required={required}
        defaultValue={defaultValue}
        className={PASSWORD_INPUT_CLASSES}
      />
    </div>
  );
}

// text_field/1
function TextField({
  label,
  hint,
  defaultValue,
  placeholder,
  disabled,
  required,
}: {
  label: string;
  hint?: ReactNode;
  defaultValue?: string;
  placeholder?: string;
  disabled?: boolean;
  required?: boolean;
}) {
  const id = useId();
  return (
    <div>
      <label
        htmlFor={id}
        className={cn(LABEL_CLASSES, 'mb-1')}
      >
        {label}
      </label>
      {hint}
      <input
        id={id}
        type="text"
        autoComplete="off"
        required={required}
        disabled={disabled}
        defaultValue={defaultValue}
        placeholder={placeholder}
        className={TEXT_FIELD_INPUT_CLASSES}
      />
    </div>
  );
}

// check_box/1
function CheckBox({
  label,
  hint,
  defaultChecked,
  disabled,
}: {
  label: string;
  hint?: ReactNode;
  defaultChecked?: boolean;
  disabled?: boolean;
}) {
  const id = useId();
  return (
    <div className="flex items-start">
      <div className="flex items-center h-5">
        <input
          id={id}
          type="checkbox"
          defaultChecked={defaultChecked}
          disabled={disabled}
          className="focus:ring-primary-500 h-4 w-4 text-primary-600 text-sm border-secondary-300 rounded disabled:bg-gray-300 focus:disabled:ring-gray-300 disabled:text-gray-300"
        />
      </div>
      <div className="ml-3 text-sm">
        <label
          htmlFor={id}
          className="font-medium text-secondary-700"
        >
          {label}
        </label>
        {hint}
      </div>
    </div>
  );
}

// label_field/1
function LabelField({
  htmlFor,
  title,
  logo,
  tooltip,
}: {
  htmlFor: string;
  title: string;
  logo?: string;
  tooltip?: string;
}) {
  const labelContent = (
    <label htmlFor={htmlFor} className={LABEL_CLASSES}>
      <div className="flex items-center">
        {title}
        {logo ? (
          <object
            data={logo}
            type="image/png"
            aria-label={`${title} logo`}
            className="w-3 h-3 ml-1"
          />
        ) : null}
      </div>
    </label>
  );

  if (tooltip) {
    return (
      <div className="flex flex-row items-end">
        {labelContent}
        <span
          className="relative ml-1 cursor-pointer"
          aria-label={tooltip}
        >
          <span className="hero-information-circle-solid w-4 h-4 text-primary-600 opacity-50" />
        </span>
      </div>
    );
  }

  return labelContent;
}

// select_field/1
function SelectField() {
  const id = useId();
  return (
    <select id={id} className={SELECT_FIELD_CLASSES} defaultValue="webhook">
      <option value="webhook">Webhook</option>
      <option value="cron">Cron</option>
      <option value="kafka">Kafka</option>
    </select>
  );
}

// select/1
function Select() {
  const id = useId();
  return (
    <select id={id} className={SELECT_CLASSES} defaultValue="staging">
      <option value="production">Production</option>
      <option value="staging">Staging</option>
      <option value="sandbox">Sandbox</option>
    </select>
  );
}

// divider/1
function Divider() {
  return (
    <div className="hidden sm:block" aria-hidden="true">
      <div className="py-5">
        <div className="border-t border-secondary-200" />
      </div>
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Legacy Form (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Fields: Story = {
  render: () => (
    <Showcase className="max-w-md">
      <Section
        title="text_field/1"
        description="Ring-bordered text input with an optional hint slot below the label."
      >
        <div className="flex flex-col gap-5">
          <TextField
            label="Workflow name"
            defaultValue="Patient sync"
            placeholder="My workflow"
          />
          <TextField
            label="Discovery URL"
            hint={
              <span className="text-xs text-secondary-500">
                The URL to the <code>.well-known</code> endpoint.
              </span>
            }
            defaultValue="https://login.example.com/.well-known/openid-configuration"
          />
          <TextField label="Read-only field" defaultValue="locked" disabled />
        </div>
      </Section>

      <Section
        title="email_field/1 & password_field/1"
        description="Secondary-styled email and password inputs."
      >
        <div className="flex flex-col gap-5">
          <EmailField label="Email" defaultValue="jane@example.org" required />
          <PasswordField label="Password" defaultValue="hunter2" required />
        </div>
      </Section>

      <Section
        title="select_field/1 & select/1"
        description="select_field/1 adds a top margin; select/1 is the bare variant."
      >
        <div className="flex flex-col gap-5">
          <div>
            <label
              htmlFor="legacy-trigger-type"
              className={cn(LABEL_CLASSES, 'mb-1')}
            >
              Trigger type
            </label>
            <SelectField />
          </div>
          <div>
            <label
              htmlFor="legacy-environment"
              className={cn(LABEL_CLASSES, 'mb-1')}
            >
              Environment
            </label>
            <Select />
          </div>
        </div>
      </Section>

      <Section
        title="check_box/1"
        description="Checkbox with a label and an optional description."
      >
        <div className="flex flex-col gap-3">
          <CheckBox label="Enabled" defaultChecked />
          <CheckBox
            label="Send notifications"
            hint={
              <p className="text-secondary-500">
                Email me when a run fails.
              </p>
            }
          />
          <CheckBox label="Locked setting" defaultChecked disabled />
        </div>
      </Section>

      <Section
        title="label_field/1"
        description="A standalone label, optionally with an adaptor logo and a tooltip trigger."
      >
        <div className="flex flex-col gap-3">
          <LabelField htmlFor="legacy-label-plain" title="API key" />
          <LabelField
            htmlFor="legacy-label-tooltip"
            title="Discovery URL"
            tooltip="The OpenID Connect discovery document."
          />
        </div>
      </Section>

      <Section
        title="text_area/1"
        description="Monospace dark textarea, used for code/body fields. Label left, errors right."
      >
        <TextArea
          label="Body"
          defaultValue={'fn(state => {\n  return state;\n})'}
        />
      </Section>

      <Section
        title="submit_button/1 & divider/1"
        description="Primary submit button (enabled and disabled) above a section divider."
      >
        <div className="flex flex-col">
          <div className="flex gap-3">
            <SubmitButton>Save</SubmitButton>
            <SubmitButton disabled>Save</SubmitButton>
          </div>
          <Divider />
        </div>
      </Section>
    </Showcase>
  ),
};
