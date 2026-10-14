import { clsx, type ClassValue } from 'clsx';
import { extendTailwindMerge } from 'tailwind-merge';

// Design token classes (assets/design-tokens/) are unknown to tailwind-merge,
// which would treat text-ds-type-body-md as a colour and drop it next to
// text-ds-subtle. Each kind of token carries a fixed word so it can be
// recognised by name: ds-type- is a font size, ds-width- a border/ring/outline
// width, ds-weight- a font weight, and any other ds- value spacing or radius.
const isDs = (value: string) => value.startsWith('ds-');
const isDsType = (value: string) => value.startsWith('ds-type-');
const isDsWidth = (value: string) => value.startsWith('ds-width-');
const isDsWeight = (value: string) => value.startsWith('ds-weight-');

const twMerge = extendTailwindMerge({
  extend: {
    theme: {
      spacing: [isDs],
      radius: [isDs],
      text: [isDsType],
      'font-weight': [isDsWeight],
    },
    classGroups: {
      'border-w': [{ border: [isDsWidth] }],
      'border-w-x': [{ 'border-x': [isDsWidth] }],
      'border-w-y': [{ 'border-y': [isDsWidth] }],
      'border-w-s': [{ 'border-s': [isDsWidth] }],
      'border-w-e': [{ 'border-e': [isDsWidth] }],
      'border-w-t': [{ 'border-t': [isDsWidth] }],
      'border-w-r': [{ 'border-r': [isDsWidth] }],
      'border-w-b': [{ 'border-b': [isDsWidth] }],
      'border-w-l': [{ 'border-l': [isDsWidth] }],
      'divide-x': [{ 'divide-x': [isDsWidth] }],
      'divide-y': [{ 'divide-y': [isDsWidth] }],
      'ring-w': [{ ring: [isDsWidth] }],
      'outline-w': [{ outline: [isDsWidth] }],
    },
  },
});

/**
 * Utility function for merging Tailwind CSS classes conditionally
 * Combines clsx for conditional class names with tailwind-merge to handle conflicts
 *
 * @example
 * cn('base-class', condition && 'conditional-class', className)
 * // => "base-class conditional-class custom-class"
 *
 * cn('p-4', 'p-2') // tailwind-merge handles conflicts
 * // => "p-2"
 */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
