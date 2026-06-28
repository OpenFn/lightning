import type { Meta, StoryObj } from '@storybook/react-vite';
import { useState } from 'react';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * React clones of `LightningWeb.Components.Common.simple_dropdown/1`,
 * `tooltip/1` and `datetime/1`
 * (lib/lightning_web/live/components/common.ex).
 *
 * Presentational only:
 *   - simple_dropdown's `phx-click`/`phx-click-away` show/hide is replaced with
 *     local `useState`; the trigger reuses the shared `.button` primary classes.
 *   - tooltip's `phx-hook="Tooltip"` (Tippy.js) is replaced with a static CSS
 *     bubble so the content is visible.
 *   - datetime's `phx-hook` time-conversion + click-to-copy are dropped; the
 *     resolved text is rendered directly for each format.
 */

// --- simple_dropdown --------------------------------------------------------
// `.button` theme="primary" base/size/theme classes (see new_inputs.ex).
const DROPDOWN_BUTTON_CLASS = cn(
  'rounded-md text-sm font-semibold shadow-xs cursor-pointer',
  'px-3 py-2',
  'bg-primary-600 hover:bg-primary-500 text-white',
  'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600',
  'relative inline-flex items-center'
);

function SimpleDropdown({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(false);

  return (
    <div className="relative inline-block">
      <div>
        <button
          type="button"
          className={DROPDOWN_BUTTON_CLASS}
          aria-expanded={open}
          aria-haspopup="true"
          onClick={() => {
            setOpen(value => !value);
          }}
        >
          {label}
          <span className="hero-chevron-down ml-1 h-5 w-5" />
        </button>
      </div>
      <div
        className={cn(
          'absolute right-0 z-40 mt-2 w-56 origin-top-right rounded-md bg-white shadow-lg ring-1 ring-black/5 focus:outline-none',
          open ? 'block' : 'hidden'
        )}
        role="menu"
        aria-orientation="vertical"
        tabIndex={-1}
      >
        <div
          className="py-1 text-sm text-gray-700 *:block *:px-4 *:py-2 *:hover:bg-gray-100"
          role="none"
        >
          {children}
        </div>
      </div>
    </div>
  );
}

// --- tooltip ----------------------------------------------------------------
function Tooltip({
  title,
  icon = 'hero-information-circle-solid',
  iconClass = 'w-4 h-4 text-primary-600 opacity-50',
}: {
  title: string;
  icon?: string;
  iconClass?: string;
}) {
  return (
    <span className="group relative ml-1 cursor-pointer" aria-label={title}>
      <span className={cn(icon, iconClass)} />
      <span
        role="tooltip"
        className="pointer-events-none absolute bottom-full left-1/2 z-50 mb-1 -translate-x-1/2 rounded bg-gray-900 px-2 py-1 text-xs whitespace-nowrap text-white opacity-0 transition-opacity group-hover:opacity-100"
      >
        {title}
      </span>
    </span>
  );
}

// --- datetime ---------------------------------------------------------------
function Datetime({
  value,
  className,
}: {
  value: string | null;
  className?: string;
}) {
  if (value === null) {
    return <span className={cn('text-gray-400', className)}>--</span>;
  }

  return (
    <span
      className={cn(
        'group relative inline-flex cursor-pointer items-center rounded transition-colors select-none',
        className
      )}
    >
      <span className="datetime-text">{value}</span>
    </span>
  );
}

const meta = {
  title: 'LiveView Clones/Dropdown (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const SimpleDropdownStory: Story = {
  name: 'simple_dropdown',
  render: () => (
    <Showcase>
      <Section
        title="simple_dropdown/1"
        description="A primary button that toggles a right-aligned menu of options. Click the trigger to open it; options highlight on hover."
      >
        <Row className="min-h-56 items-start">
          <SimpleDropdown label="Run">
            <button type="button">Run now</button>
            <button type="button">Run with custom input</button>
            <button type="button">Retry from start</button>
          </SimpleDropdown>
        </Row>
      </Section>
    </Showcase>
  ),
};

export const TooltipStory: Story = {
  name: 'tooltip',
  render: () => (
    <Showcase>
      <Section
        title="tooltip/1"
        description="A small info icon that reveals a hint on hover. The real component uses Tippy.js via phx-hook; here a static CSS bubble stands in. Hover the icon to reveal it."
      >
        <Row className="gap-8">
          <Specimen label="default icon">
            <span className="inline-flex items-center text-sm font-medium text-gray-900">
              Concurrency
              <Tooltip title="The maximum number of runs processed at once." />
            </span>
          </Specimen>
          <Specimen label="custom icon">
            <span className="inline-flex items-center text-sm font-medium text-gray-900">
              Danger zone
              <Tooltip
                title="These actions cannot be undone."
                icon="hero-exclamation-triangle"
                iconClass="w-4 h-4 text-red-500"
              />
            </span>
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};

export const DatetimeStory: Story = {
  name: 'datetime',
  render: () => (
    <Showcase>
      <Section
        title="datetime/1"
        description="Renders a timestamp with click-to-copy and a hover tooltip in the app. The supported formats produce different text; the nil case renders a muted placeholder."
      >
        <div className="flex flex-col gap-3 text-sm text-gray-700">
          <Specimen label="format={:relative}">
            <Datetime value="2 hours ago" />
          </Specimen>
          <Specimen label="format={:relative_detailed}">
            <Datetime value="2 hours ago (2024-01-15 14:30:00)" />
          </Specimen>
          <Specimen label="format={:detailed}">
            <Datetime value="2024-01-15 14:30:00" />
          </Specimen>
          <Specimen label="format={:time_only}">
            <Datetime value="14:30:00" />
          </Specimen>
          <Specimen label="datetime={nil}">
            <Datetime value={null} />
          </Specimen>
        </div>
      </Section>
    </Showcase>
  ),
};
