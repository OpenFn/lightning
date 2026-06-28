import type { Meta, StoryObj } from '@storybook/react-vite';
import type { ReactNode } from 'react';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clone of `LightningWeb.Components.Icon`
 * (lib/lightning_web/live/components/icon.ex), the set of Lightning-specific
 * named icons.
 *
 * The heroicon-backed entries (`workflows`, `sandboxes`, `channels`, `runs`,
 * `pencil`, `exclamation_circle`, `settings`, `dataclips`, `info`) simply
 * delegate to a Heroicon, so they are rendered with the Tailwind `hero-*` mask
 * spans. The hand-authored SVGs (`branches`, `left`, `right`, `trash`, `plus`,
 * `plus_circle`, `eye`, `chevron_left`, `chevron_right`) are inlined verbatim
 * from the source module. Presentational only.
 */

// --- Hand-authored SVGs, copied from icon.ex --------------------------------
// Mirrors the shared `outer_svg/1` wrapper used by several of the icons below.
function OuterSvg({ children }: { children: ReactNode }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth="2"
      className="inline-block h-5 w-5"
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

function BranchesIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      className="h-5 w-5"
      aria-hidden="true"
    >
      <circle cx="6" cy="6" r="2.25" />
      <circle cx="18" cy="6" r="2.25" />
      <circle cx="18" cy="18" r="2.25" />
      <path d="M6 8v10a4 4 0 0 0 4 4h8" />
      <path d="M8 6h8" />
    </svg>
  );
}

function LeftIcon() {
  return (
    <OuterSvg>
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M11 17l-5-5m0 0l5-5m-5 5h12"
      />
    </OuterSvg>
  );
}

function RightIcon() {
  return (
    <OuterSvg>
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M13 7l5 5m0 0l-5 5m5-5H6"
      />
    </OuterSvg>
  );
}

function TrashIcon() {
  return (
    <OuterSvg>
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
      />
    </OuterSvg>
  );
}

function PlusIcon() {
  return (
    <OuterSvg>
      <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
    </OuterSvg>
  );
}

function PlusCircleIcon() {
  return (
    <OuterSvg>
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M12 9v6m3-3H9m12 0a9 9 0 11-18 0 9 9 0 0118 0z"
      />
    </OuterSvg>
  );
}

function EyeIcon() {
  return (
    <OuterSvg>
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
      />
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
      />
    </OuterSvg>
  );
}

function ChevronLeftIcon() {
  return (
    <svg
      className="h-5 w-5"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 20 20"
      fill="currentColor"
      aria-hidden="true"
    >
      <path
        fillRule="evenodd"
        d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z"
        clipRule="evenodd"
      />
    </svg>
  );
}

function ChevronRightIcon() {
  return (
    <svg
      className="h-5 w-5"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 20 20"
      fill="currentColor"
      aria-hidden="true"
    >
      <path
        fillRule="evenodd"
        d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
        clipRule="evenodd"
      />
    </svg>
  );
}

// --- Gallery ----------------------------------------------------------------
interface IconEntry {
  name: string;
  source: string;
  icon: ReactNode;
}

// Heroicon delegations, rendered via the Tailwind `hero-*` mask spans.
const HEROICON_ENTRIES: IconEntry[] = [
  {
    name: 'workflows',
    source: 'Heroicons.square_3_stack_3d',
    icon: <span className="hero-square-3-stack-3d size-5" />,
  },
  {
    name: 'sandboxes',
    source: 'Heroicons.beaker',
    icon: <span className="hero-beaker size-5" />,
  },
  {
    name: 'channels',
    source: 'Heroicons.arrows_right_left',
    icon: <span className="hero-arrows-right-left size-5" />,
  },
  {
    name: 'runs',
    source: 'Heroicons.rectangle_stack',
    icon: <span className="hero-rectangle-stack size-5" />,
  },
  {
    name: 'pencil',
    source: 'Heroicons.pencil',
    icon: <span className="hero-pencil size-5" />,
  },
  {
    name: 'exclamation_circle',
    source: 'Heroicons.exclamation_circle',
    icon: <span className="hero-exclamation-circle size-5" />,
  },
  {
    name: 'settings',
    source: 'Heroicons.cog_8_tooth',
    icon: <span className="hero-cog-8-tooth size-5" />,
  },
  {
    name: 'dataclips',
    source: 'Heroicons.cube',
    icon: <span className="hero-cube size-5" />,
  },
  {
    name: 'info',
    source: 'Heroicons.information_circle',
    icon: <span className="hero-information-circle size-5" />,
  },
];

// Hand-authored inline SVGs.
const CUSTOM_ENTRIES: IconEntry[] = [
  { name: 'branches', source: 'inline svg', icon: <BranchesIcon /> },
  { name: 'left', source: 'inline svg', icon: <LeftIcon /> },
  { name: 'right', source: 'inline svg', icon: <RightIcon /> },
  { name: 'trash', source: 'inline svg', icon: <TrashIcon /> },
  { name: 'plus', source: 'inline svg', icon: <PlusIcon /> },
  { name: 'plus_circle', source: 'inline svg', icon: <PlusCircleIcon /> },
  { name: 'eye', source: 'inline svg', icon: <EyeIcon /> },
  { name: 'chevron_left', source: 'inline svg', icon: <ChevronLeftIcon /> },
  { name: 'chevron_right', source: 'inline svg', icon: <ChevronRightIcon /> },
];

function IconTile({ entry }: { entry: IconEntry }) {
  return (
    <div className="flex w-28 flex-col items-center gap-2 rounded-lg border border-gray-200 bg-white p-4 text-gray-700">
      <div className="flex h-8 items-center justify-center">{entry.icon}</div>
      <span className="font-mono text-[11px] text-gray-700">{entry.name}</span>
      <span className="text-center font-mono text-[10px] text-gray-400">
        {entry.source}
      </span>
    </div>
  );
}

function IconGrid({ entries }: { entries: IconEntry[] }) {
  return (
    <div className="flex flex-wrap gap-3">
      {entries.map(entry => (
        <IconTile key={entry.name} entry={entry} />
      ))}
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Icon Set (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Gallery: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Heroicon delegations"
        description="Named icons that delegate straight to a Heroicon. Rendered here with the Tailwind hero-* mask spans."
      >
        <IconGrid entries={HEROICON_ENTRIES} />
      </Section>
      <Section
        title="Hand-authored SVGs"
        description="Icons defined inline in icon.ex, copied verbatim. branches uses a 1.5 stroke; the chevrons use a 20x20 filled viewBox; the rest share the outer_svg wrapper."
      >
        <IconGrid entries={CUSTOM_ENTRIES} />
      </Section>
    </Showcase>
  ),
};
