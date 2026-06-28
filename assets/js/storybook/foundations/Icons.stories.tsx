import type { Meta, StoryObj } from '@storybook/react-vite';

import { Showcase, Section } from '../_shared/showcase';

/**
 * Icons are embedded as CSS mask utilities by the Tailwind plugin in
 * `tailwind.config.ts` (see `CoreComponents.icon/1`). Heroicons come in four
 * variants — outline (`hero-name`), solid (`hero-name-solid`), mini
 * (`hero-name-mini`, 20px) and micro (`hero-name-micro`, 16px). A small set of
 * Lucide icons is also vendored.
 *
 * Color and size follow `currentColor`/`width`/`height`, so any text color or
 * `size-*` utility tints and scales them. Class names are literal so Tailwind
 * emits the masks.
 */
const HERO_OUTLINE: readonly string[] = [
  'hero-x-mark',
  'hero-arrow-path',
  'hero-chevron-down',
  'hero-chevron-up',
  'hero-chevron-right',
  'hero-chevron-left',
  'hero-exclamation-triangle',
  'hero-exclamation-circle',
  'hero-information-circle',
  'hero-check',
  'hero-check-circle',
  'hero-x-circle',
  'hero-plus',
  'hero-plus-circle',
  'hero-minus-circle',
  'hero-trash',
  'hero-pencil-square',
  'hero-document-text',
  'hero-document-duplicate',
  'hero-folder',
  'hero-rectangle-stack',
  'hero-magnifying-glass',
  'hero-adjustments-vertical',
  'hero-beaker',
  'hero-sparkles',
  'hero-bolt',
  'hero-clock',
  'hero-calendar',
  'hero-key',
  'hero-lock-closed',
  'hero-shield-exclamation',
  'hero-eye',
  'hero-eye-slash',
  'hero-globe-alt',
  'hero-link',
  'hero-paper-airplane',
  'hero-chat-bubble-left-right',
  'hero-user',
  'hero-users',
  'hero-bell',
  'hero-cog-6-tooth',
  'hero-ellipsis-vertical',
];

const HERO_VARIANTS: readonly { cls: string; label: string }[] = [
  { cls: 'hero-bell size-6', label: 'hero-bell' },
  { cls: 'hero-bell-solid size-6', label: 'hero-bell-solid' },
  { cls: 'hero-bell-mini size-5', label: 'hero-bell-mini' },
  { cls: 'hero-bell-micro size-4', label: 'hero-bell-micro' },
];

const LUCIDE: readonly string[] = [
  'lucide-circle-dot',
  'lucide-square-arrow-up',
  'lucide-square-arrow-down',
  'lucide-square-arrow-left',
  'lucide-square-arrow-right',
  'lucide-square-arrow-up-left',
  'lucide-square-arrow-up-right',
  'lucide-square-arrow-down-left',
  'lucide-square-arrow-down-right',
  'lucide-square-arrow-right-enter',
  'lucide-square-arrow-right-exit',
  'lucide-square-arrow-out-up-left',
  'lucide-square-arrow-out-up-right',
  'lucide-square-arrow-out-down-left',
  'lucide-square-arrow-out-down-right',
];

function IconTile({ cls, label }: { cls: string; label: string }) {
  return (
    <div className="flex w-24 flex-col items-center gap-2 rounded-md border border-gray-100 p-3 text-gray-700">
      <span className={cls} />
      <span className="w-full truncate text-center font-mono text-[10px] text-gray-500">
        {label}
      </span>
    </div>
  );
}

function IconGallery() {
  return (
    <Showcase className="min-w-[760px]">
      <Section
        title="Variants"
        description="The same icon across the four heroicon variants and their default sizes."
      >
        <div className="flex flex-wrap gap-3 text-primary-600">
          {HERO_VARIANTS.map(variant => (
            <IconTile
              key={variant.label}
              cls={variant.cls}
              label={variant.label}
            />
          ))}
        </div>
      </Section>

      <Section
        title="Heroicons (outline)"
        description="A selection of the most-used outline icons. Add `-solid`, `-mini` or `-micro` for the other variants."
      >
        <div className="flex flex-wrap gap-3">
          {HERO_OUTLINE.map(cls => (
            <IconTile
              key={cls}
              cls={`${cls} size-6`}
              label={cls.replace('hero-', '')}
            />
          ))}
        </div>
      </Section>

      <Section
        title="Lucide (vendored subset)"
        description="Used by the workflow diagram edge/path indicators. Add more SVGs under vendor/lucide/optimized/ to extend."
      >
        <div className="flex flex-wrap gap-3 text-gray-700">
          {LUCIDE.map(cls => (
            <IconTile
              key={cls}
              cls={`${cls} size-6`}
              label={cls.replace('lucide-', '')}
            />
          ))}
        </div>
      </Section>
    </Showcase>
  );
}

const meta = {
  title: 'Foundations/Icons',
  component: IconGallery,
  parameters: { layout: 'fullscreen' },
} satisfies Meta<typeof IconGallery>;

export default meta;

export const Gallery: StoryObj<typeof meta> = {};
