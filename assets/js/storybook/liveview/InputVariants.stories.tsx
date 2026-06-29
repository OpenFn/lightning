import type { Meta, StoryObj } from '@storybook/react-vite';
import { useId, useState } from 'react';
import type { AnchorHTMLAttributes, ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * React clones of components in
 * `LightningWeb.Components.NewInputs` (lib/lightning_web/components/new_inputs.ex):
 * `button_link/1`, `simple_button_with_tooltip/1`, and the `input/1` variants
 * `type="select"`, `type="password"`, `type="radio"` and `type="tag"`.
 *
 * Presentational only. The `phx-submit-loading:opacity-75` class and all
 * `phx-*`/JS bindings (eye-toggle, TagInput hook, tooltip hook) are dropped;
 * the password reveal and tag removal use local React state instead.
 */

// --- shared button_link styling --------------------------------------------
type ButtonTheme = 'primary' | 'secondary' | 'danger' | 'success' | 'warning';
type ButtonSize = 'sm' | 'md' | 'lg';

const BUTTON_BASE = 'rounded-md text-sm font-semibold shadow-xs';

const SIZE_CLASSES: Record<ButtonSize, string> = {
  sm: 'px-2.5 py-1.5',
  md: 'px-3 py-2',
  lg: 'px-3.5 py-2.5',
};

const THEME_ENABLED: Record<ButtonTheme, string> = {
  primary:
    'bg-primary-600 hover:bg-primary-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600',
  secondary:
    'bg-white hover:bg-gray-50 text-gray-900 ring-1 ring-gray-300 ring-inset',
  danger:
    'bg-red-600 hover:bg-red-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600',
  success:
    'bg-green-600 hover:bg-green-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-green-600',
  warning:
    'bg-yellow-600 hover:bg-yellow-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-yellow-600',
};

const THEME_DISABLED: Record<ButtonTheme, string> = {
  primary: 'bg-primary-300 text-white',
  secondary: 'bg-gray-50 text-gray-400 ring-1 ring-gray-200 ring-inset',
  danger: 'bg-red-300 text-white',
  success: 'bg-green-300 text-white',
  warning: 'bg-yellow-300 text-white',
};

const THEMES: ButtonTheme[] = [
  'primary',
  'secondary',
  'danger',
  'success',
  'warning',
];

// button_link/1
interface ButtonLinkProps
  extends Omit<AnchorHTMLAttributes<HTMLAnchorElement>, 'href'> {
  theme: ButtonTheme;
  size?: ButtonSize;
  disabled?: boolean;
  href?: string;
  children: ReactNode;
}

function ButtonLink({
  theme,
  size = 'md',
  disabled = false,
  href = '#',
  className,
  children,
  ...rest
}: ButtonLinkProps) {
  if (disabled) {
    return (
      <span
        aria-disabled="true"
        className={cn(
          BUTTON_BASE,
          'inline-block',
          SIZE_CLASSES[size],
          THEME_DISABLED[theme],
          'pointer-events-none cursor-not-allowed',
          className
        )}
      >
        {children}
      </span>
    );
  }

  return (
    <a
      href={href}
      className={cn(
        BUTTON_BASE,
        'inline-block',
        SIZE_CLASSES[size],
        THEME_ENABLED[theme],
        className
      )}
      {...rest}
    >
      {children}
    </a>
  );
}

// simple_button_with_tooltip/1
function SimpleButtonWithTooltip({
  tooltip,
  disabled,
  children,
}: {
  tooltip?: string;
  disabled?: boolean;
  children: ReactNode;
}) {
  const button = (
    <button
      type="button"
      disabled={disabled}
      className={cn(
        BUTTON_BASE,
        'cursor-pointer disabled:cursor-auto',
        SIZE_CLASSES.md,
        disabled ? THEME_DISABLED.primary : THEME_ENABLED.primary
      )}
    >
      {children}
    </button>
  );

  if (disabled && tooltip) {
    return <span aria-label={tooltip}>{button}</span>;
  }

  return button;
}

// input type="select"
function SelectInput({
  label,
  required,
  tooltip,
}: {
  label: string;
  required?: boolean;
  tooltip?: string;
}) {
  const id = useId();
  return (
    <div>
      <label
        htmlFor={id}
        className="text-sm/6 font-medium text-slate-800 mb-2"
      >
        {label}
        {required ? <span className="text-red-500"> *</span> : null}
        {tooltip ? (
          <span
            className="relative cursor-pointer inline-block align-super ml-1"
            aria-label={tooltip}
          >
            <span className="hero-information-circle-solid w-4 h-4 text-primary-600 opacity-50" />
          </span>
        ) : null}
      </label>
      <div className="flex w-full">
        <div className="relative items-center w-full">
          <select
            id={id}
            defaultValue="dhis2"
            className="block w-full rounded-lg border border-secondary-300 bg-white sm:text-sm shadow-xs focus:border-primary-300 focus:ring focus:ring-primary-200/50 disabled:cursor-not-allowed"
          >
            <option value="dhis2">@openfn/language-dhis2</option>
            <option value="http">@openfn/language-http</option>
            <option value="salesforce">@openfn/language-salesforce</option>
          </select>
        </div>
      </div>
    </div>
  );
}

// input type="password"
function PasswordInput({
  label,
  defaultValue,
  error,
}: {
  label: string;
  defaultValue?: string;
  error?: string;
}) {
  const id = useId();
  const [revealed, setRevealed] = useState(false);
  return (
    <div>
      <label
        htmlFor={id}
        className="text-sm/6 font-medium text-slate-800"
      >
        {label}
      </label>
      <div className="relative mt-2 rounded-lg shadow-xs">
        <input
          id={id}
          autoComplete="off"
          type={revealed ? 'text' : 'password'}
          defaultValue={defaultValue}
          className={cn(
            'focus:outline focus:outline-2 focus:outline-offset-1 block w-full rounded-lg text-slate-900 focus:ring-0 sm:text-sm sm:leading-6',
            'disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500',
            error
              ? 'border-danger-400 focus:border-danger-400 focus:outline-danger-400'
              : 'border-slate-300 focus:border-slate-400 focus:outline-primary-600'
          )}
        />
        <div className="absolute inset-y-0 right-0 flex items-center pr-3">
          <button
            type="button"
            aria-label={revealed ? 'Hide password' : 'Show password'}
            onClick={() => {
              setRevealed(value => !value);
            }}
          >
            <span
              className={cn(
                revealed ? 'hero-eye' : 'hero-eye-slash',
                'h-5 w-5 cursor-pointer'
              )}
            />
          </button>
        </div>
      </div>
      {error ? (
        <div className="error-space">
          <p
            data-tag="error_message"
            className="mt-1 inline-flex items-center gap-x-1.5 text-xs text-danger-600"
          >
            <span className="hero-exclamation-circle h-4 w-4" />
            {error}
          </p>
        </div>
      ) : null}
    </div>
  );
}

// input type="radio"
function RadioInput({
  name,
  value,
  label,
  defaultChecked,
}: {
  name: string;
  value: string;
  label: string;
  defaultChecked?: boolean;
}) {
  const id = useId();
  return (
    <label
      htmlFor={id}
      className="flex items-center gap-2 text-sm text-slate-600"
    >
      <input
        id={id}
        type="radio"
        name={name}
        value={value}
        defaultChecked={defaultChecked}
        className="h-4 w-4 border-gray-300 text-primary-600 focus:ring-primary-600"
      />
      {label}
    </label>
  );
}

// input type="tag"
function TagInput({
  label,
  sublabel,
  placeholder,
  initialTags,
}: {
  label: string;
  sublabel?: string;
  placeholder?: string;
  initialTags: string[];
}) {
  const id = useId();
  const [tags, setTags] = useState(initialTags);
  return (
    <div className="tag-input-container">
      <label
        htmlFor={id}
        className="text-sm/6 font-medium text-slate-800 mb-2"
      >
        {label}
      </label>
      {sublabel ? (
        <small className="mb-2 block text-xs text-gray-600">{sublabel}</small>
      ) : null}
      <div className="relative">
        <input
          id={id}
          type="text"
          placeholder={placeholder}
          className="focus:outline focus:outline-2 focus:outline-offset-1 block w-full rounded-lg text-slate-900 focus:ring-0 sm:text-sm sm:leading-6 disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500 border-slate-300 focus:border-slate-400 focus:outline-primary-600"
        />
      </div>
      <div className="tag-list mt-2">
        {tags.map(tag => (
          <span
            key={tag}
            data-tag={tag}
            className="inline-flex items-center rounded-md bg-blue-50 p-2 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10 mr-1 my-1"
          >
            {tag}
            <button
              type="button"
              onClick={() => {
                setTags(current => current.filter(t => t !== tag));
              }}
              className="group relative -mr-1 h-3.5 w-3.5 rounded-sm hover:bg-gray-500/20"
            >
              <span className="sr-only">Remove</span>
              <span className="hero-x-mark h-3 w-3 stroke-gray-600/50 group-hover:stroke-gray-600/75" />
            </button>
          </span>
        ))}
      </div>
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Input Variants (LiveView Clone)',
  tags: ['useful', 'modular'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Buttons: Story = {
  render: () => (
    <Showcase>
      <Section
        title="button_link/1"
        description="A link styled as a button. Themed identically to button/1; disabled renders a non-interactive span."
      >
        <Row>
          {THEMES.map(theme => (
            <ButtonLink key={theme} theme={theme}>
              {theme}
            </ButtonLink>
          ))}
        </Row>
      </Section>

      <Section title="button_link/1 — disabled">
        <Row>
          {THEMES.map(theme => (
            <ButtonLink key={theme} theme={theme} disabled>
              {theme}
            </ButtonLink>
          ))}
        </Row>
      </Section>

      <Section
        title="simple_button_with_tooltip/1"
        description="A plain button; when disabled with a tooltip it is wrapped so the reason can be surfaced on hover."
      >
        <Row>
          <Specimen label="enabled">
            <SimpleButtonWithTooltip>Run now</SimpleButtonWithTooltip>
          </Specimen>
          <Specimen label="disabled + tooltip">
            <SimpleButtonWithTooltip
              disabled
              tooltip="You don't have permission to run this workflow."
            >
              Run now
            </SimpleButtonWithTooltip>
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};

export const Inputs: Story = {
  render: () => (
    <Showcase className="max-w-md">
      <Section
        title='input type="select"'
        description="Rounded select with label, optional required marker and tooltip."
      >
        <div className="flex flex-col gap-5">
          <SelectInput label="Adaptor" />
          <SelectInput
            label="Adaptor"
            required
            tooltip="The NPM adaptor used to run this job."
          />
        </div>
      </Section>

      <Section
        title='input type="password"'
        description="Password field with a show/hide eye toggle. Click the eye to reveal."
      >
        <div className="flex flex-col gap-5">
          <PasswordInput label="Client secret" defaultValue="s3cr3t-value" />
          <PasswordInput
            label="Client secret"
            defaultValue="too-short"
            error="should be at least 16 character(s)"
          />
        </div>
      </Section>

      <Section
        title='input type="radio"'
        description="Bare radio inputs, typically composed into a labelled group."
      >
        <fieldset className="flex flex-col gap-2">
          <legend className="text-sm/6 font-medium text-slate-800 mb-2">
            Run condition
          </legend>
          <RadioInput
            name="condition"
            value="always"
            label="Always"
            defaultChecked
          />
          <RadioInput
            name="condition"
            value="on_success"
            label="On success"
          />
          <RadioInput
            name="condition"
            value="on_failure"
            label="On failure"
          />
        </fieldset>
      </Section>

      <Section
        title='input type="tag"'
        description="Comma-separated tag input. The chips below mirror the committed values; click ✕ to remove one."
      >
        <TagInput
          label="Allowed hosts"
          sublabel="Requests are only permitted to these domains."
          placeholder="Type a host and press enter"
          initialTags={['api.example.org', 'dhis2.example.org', 'localhost']}
        />
      </Section>
    </Showcase>
  ),
};
