import type { Meta, StoryObj } from '@storybook/react-vite';

import { Showcase, Section } from '../_shared/showcase';

/**
 * The semantic color scales defined in `assets/css/app.css` (`@theme`). Each
 * scale is an alias of a built-in Tailwind palette, so changing the alias in
 * `app.css` re-themes the whole app.
 *
 * Class names are written out literally below because Tailwind v4 only emits
 * the utilities (and their theme variables) that actually appear in source.
 */
const SHADES = [
  '50',
  '100',
  '200',
  '300',
  '400',
  '500',
  '600',
  '700',
  '800',
  '900',
  '950',
] as const;

interface Scale {
  name: string;
  alias: string;
  classes: readonly string[];
}

const SEMANTIC_SCALES: readonly Scale[] = [
  {
    name: 'primary',
    alias: 'indigo',
    classes: [
      'bg-primary-50',
      'bg-primary-100',
      'bg-primary-200',
      'bg-primary-300',
      'bg-primary-400',
      'bg-primary-500',
      'bg-primary-600',
      'bg-primary-700',
      'bg-primary-800',
      'bg-primary-900',
      'bg-primary-950',
    ],
  },
  {
    name: 'secondary',
    alias: 'gray',
    classes: [
      'bg-secondary-50',
      'bg-secondary-100',
      'bg-secondary-200',
      'bg-secondary-300',
      'bg-secondary-400',
      'bg-secondary-500',
      'bg-secondary-600',
      'bg-secondary-700',
      'bg-secondary-800',
      'bg-secondary-900',
      'bg-secondary-950',
    ],
  },
  {
    name: 'info',
    alias: 'sky',
    classes: [
      'bg-info-50',
      'bg-info-100',
      'bg-info-200',
      'bg-info-300',
      'bg-info-400',
      'bg-info-500',
      'bg-info-600',
      'bg-info-700',
      'bg-info-800',
      'bg-info-900',
      'bg-info-950',
    ],
  },
  {
    name: 'success',
    alias: 'green',
    classes: [
      'bg-success-50',
      'bg-success-100',
      'bg-success-200',
      'bg-success-300',
      'bg-success-400',
      'bg-success-500',
      'bg-success-600',
      'bg-success-700',
      'bg-success-800',
      'bg-success-900',
      'bg-success-950',
    ],
  },
  {
    name: 'danger',
    alias: 'red',
    classes: [
      'bg-danger-50',
      'bg-danger-100',
      'bg-danger-200',
      'bg-danger-300',
      'bg-danger-400',
      'bg-danger-500',
      'bg-danger-600',
      'bg-danger-700',
      'bg-danger-800',
      'bg-danger-900',
      'bg-danger-950',
    ],
  },
  {
    name: 'warning',
    alias: 'yellow',
    classes: [
      'bg-warning-50',
      'bg-warning-100',
      'bg-warning-200',
      'bg-warning-300',
      'bg-warning-400',
      'bg-warning-500',
      'bg-warning-600',
      'bg-warning-700',
      'bg-warning-800',
      'bg-warning-900',
      'bg-warning-950',
    ],
  },
];

const NEUTRAL_SCALES: readonly Scale[] = [
  {
    name: 'slate',
    alias: 'tailwind',
    classes: [
      'bg-slate-50',
      'bg-slate-100',
      'bg-slate-200',
      'bg-slate-300',
      'bg-slate-400',
      'bg-slate-500',
      'bg-slate-600',
      'bg-slate-700',
      'bg-slate-800',
      'bg-slate-900',
      'bg-slate-950',
    ],
  },
  {
    name: 'gray',
    alias: 'tailwind',
    classes: [
      'bg-gray-50',
      'bg-gray-100',
      'bg-gray-200',
      'bg-gray-300',
      'bg-gray-400',
      'bg-gray-500',
      'bg-gray-600',
      'bg-gray-700',
      'bg-gray-800',
      'bg-gray-900',
      'bg-gray-950',
    ],
  },
];

function ScaleRow({ scale }: { scale: Scale }) {
  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-baseline gap-2">
        <span className="w-24 text-sm font-medium text-gray-900">
          {scale.name}
        </span>
        <span className="font-mono text-xs text-gray-400">→ {scale.alias}</span>
      </div>
      <div className="flex gap-1">
        {scale.classes.map((cls, index) => {
          const shade = SHADES[index] ?? '';
          return (
            <div key={cls} className="flex flex-col items-center gap-1">
              <div
                className={`h-12 w-12 rounded-md ring-1 ring-black/5 ${cls}`}
              />
              <span className="font-mono text-[10px] text-gray-500">
                {shade}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function Palette() {
  return (
    <Showcase className="min-w-[760px]">
      <Section
        title="Semantic scales"
        description="Named scales from app.css. Use these (e.g. bg-primary-600, text-danger-700) instead of the raw Tailwind palette so the app can be re-themed centrally."
      >
        <div className="flex flex-col gap-5">
          {SEMANTIC_SCALES.map(scale => (
            <ScaleRow key={scale.name} scale={scale} />
          ))}
        </div>
      </Section>
      <Section
        title="Neutrals"
        description="The raw Tailwind grays used heavily across surfaces, borders and text."
      >
        <div className="flex flex-col gap-5">
          {NEUTRAL_SCALES.map(scale => (
            <ScaleRow key={scale.name} scale={scale} />
          ))}
        </div>
      </Section>
    </Showcase>
  );
}

const meta = {
  title: 'Foundations/Colors',
  tags: ['foundation'],
  component: Palette,
  parameters: { layout: 'fullscreen' },
} satisfies Meta<typeof Palette>;

export default meta;

export const Palettes: StoryObj<typeof meta> = {};
