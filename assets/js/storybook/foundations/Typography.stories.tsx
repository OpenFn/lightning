import type { Meta, StoryObj } from '@storybook/react-vite';

import { Showcase, Section } from '../_shared/showcase';

/**
 * Type families and scale. Lightning uses `Inter var` for UI text
 * (`font-sans`) and `Fira Code VF` for code and identifiers (`font-mono`),
 * both defined in `app.css` `@theme`.
 */
const SIZES = [
  { cls: 'text-xs', label: 'text-xs · 0.75rem' },
  { cls: 'text-sm', label: 'text-sm · 0.875rem' },
  { cls: 'text-base', label: 'text-base · 1rem' },
  { cls: 'text-lg', label: 'text-lg · 1.125rem' },
  { cls: 'text-xl', label: 'text-xl · 1.25rem' },
  { cls: 'text-2xl', label: 'text-2xl · 1.5rem' },
  { cls: 'text-3xl', label: 'text-3xl · 1.875rem' },
  { cls: 'text-4xl', label: 'text-4xl · 2.25rem' },
] as const;

const WEIGHTS = [
  { cls: 'font-light', label: 'font-light · 300' },
  { cls: 'font-normal', label: 'font-normal · 400' },
  { cls: 'font-medium', label: 'font-medium · 500' },
  { cls: 'font-semibold', label: 'font-semibold · 600' },
  { cls: 'font-bold', label: 'font-bold · 700' },
] as const;

function TypeSpecimens() {
  return (
    <Showcase className="min-w-[640px]">
      <Section title="Families">
        <div className="flex flex-col gap-4">
          <div className="flex flex-col gap-1">
            <p className="font-sans text-2xl text-gray-900">
              The quick brown fox jumps over the lazy dog
            </p>
            <span className="font-mono text-xs text-gray-500">
              font-sans · Inter var
            </span>
          </div>
          <div className="flex flex-col gap-1">
            <p className="font-mono text-2xl text-gray-900">
              const run = workflow.execute(state);
            </p>
            <span className="font-mono text-xs text-gray-500">
              font-mono · Fira Code VF
            </span>
          </div>
        </div>
      </Section>

      <Section title="Sizes">
        <div className="flex flex-col gap-3">
          {SIZES.map(size => (
            <div key={size.cls} className="flex items-baseline gap-4">
              <span className="w-40 shrink-0 font-mono text-xs text-gray-500">
                {size.label}
              </span>
              <span className={`${size.cls} text-gray-900`}>
                Move health &amp; survey data
              </span>
            </div>
          ))}
        </div>
      </Section>

      <Section title="Weights">
        <div className="flex flex-col gap-3">
          {WEIGHTS.map(weight => (
            <div key={weight.cls} className="flex items-baseline gap-4">
              <span className="w-40 shrink-0 font-mono text-xs text-gray-500">
                {weight.label}
              </span>
              <span className={`text-lg text-gray-900 ${weight.cls}`}>
                Move health &amp; survey data
              </span>
            </div>
          ))}
        </div>
      </Section>
    </Showcase>
  );
}

const meta = {
  title: 'Foundations/Typography',
  tags: ['foundation'],
  component: TypeSpecimens,
  parameters: { layout: 'fullscreen' },
} satisfies Meta<typeof TypeSpecimens>;

export default meta;

export const Type: StoryObj<typeof meta> = {};
