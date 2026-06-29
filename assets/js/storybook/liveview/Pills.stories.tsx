import type { Meta, StoryObj } from '@storybook/react-vite';
import { useState } from 'react';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section, Row } from '../_shared/showcase';

/**
 * React clones of `LightningWeb.Components.Pills`
 * (lib/lightning_web/components/pills.ex): `pill/1`, `filter_chip/1` and
 * `name_badge/1`. Presentational only — the `phx-click` filter-clearing
 * behaviour of `filter_chip` is replaced with local state.
 */
type PillColor =
  | 'gray'
  | 'red'
  | 'yellow'
  | 'green'
  | 'blue'
  | 'indigo'
  | 'purple'
  | 'pink';

const PILL_COLORS: Record<PillColor, string> = {
  gray: 'bg-gray-100 text-gray-600',
  red: 'bg-red-100 text-red-700',
  yellow: 'bg-yellow-100 text-yellow-800',
  green: 'bg-green-100 text-green-700',
  blue: 'bg-blue-100 text-blue-700',
  indigo: 'bg-indigo-100 text-indigo-700',
  purple: 'bg-purple-100 text-purple-700',
  pink: 'bg-pink-100 text-pink-700',
};

function Pill({
  color = 'gray',
  children,
}: {
  color?: PillColor;
  children: ReactNode;
}) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
        PILL_COLORS[color]
      )}
    >
      {children}
    </span>
  );
}

function FilterChip({
  active,
  clearable,
  children,
}: {
  active: boolean;
  clearable: boolean;
  children: ReactNode;
}) {
  const [cleared, setCleared] = useState(false);
  const isActive = active && !cleared;
  return (
    <div
      className={cn(
        'inline-flex items-center gap-x-1 rounded-full pl-3 text-sm font-medium transition-colors py-1.5',
        isActive
          ? 'bg-indigo-50 text-indigo-700 border border-indigo-200'
          : 'bg-gray-100 text-gray-700 border border-gray-200 hover:bg-gray-200',
        isActive && clearable ? 'pr-1.5' : 'pr-3'
      )}
    >
      <button type="button" className="cursor-pointer">
        {children}
      </button>
      {isActive && clearable ? (
        <button
          type="button"
          className="group flex h-5 w-5 items-center justify-center rounded-full hover:bg-indigo-200"
          aria-label="Clear filter"
          onClick={() => {
            setCleared(true);
          }}
        >
          <span className="hero-x-mark-solid h-3 w-3 text-indigo-400 group-hover:text-indigo-600" />
        </button>
      ) : null}
    </div>
  );
}

function NameBadge({ name, children }: { name: string; children: ReactNode }) {
  if (!name) return null;
  return (
    <span>
      {children}
      <span className="ml-1 rounded-md border border-slate-300 bg-yellow-100 p-1 font-mono text-xs">
        {name}
      </span>
      .
    </span>
  );
}

const meta = {
  title: 'LiveView Clones/Pills (LiveView Clone)',
  tags: ['core'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Pills: Story = {
  render: () => (
    <Showcase>
      <Section
        title="pill/1"
        description="Rounded tag in eight colors (gray is the default)."
      >
        <Row>
          {(Object.keys(PILL_COLORS) as PillColor[]).map(color => (
            <Pill key={color} color={color}>
              {color}
            </Pill>
          ))}
        </Row>
      </Section>

      <Section
        title="filter_chip/1"
        description="A filter chip that doubles as a dropdown trigger. Gray when inactive, indigo when a filter is active; the active + clearable variant shows a clear button."
      >
        <Row>
          <FilterChip active={false} clearable={false}>
            Status
          </FilterChip>
          <FilterChip active clearable={false}>
            Status: success
          </FilterChip>
          <FilterChip active clearable>
            Status: success
          </FilterChip>
        </Row>
      </Section>

      <Section
        title="name_badge/1"
        description="Previews a derived URL-safe name inside a yellow badge."
      >
        <Row>
          <NameBadge name="my-first-project">
            Your project will be named
          </NameBadge>
        </Row>
      </Section>
    </Showcase>
  ),
};
