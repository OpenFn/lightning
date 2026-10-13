import { clsx, type ClassValue } from 'clsx';
import { extendTailwindMerge } from 'tailwind-merge';

// The design token classes (text-body-sm, p-sm, border-sm), written by
// bin/design-tokens. Without them tailwind-merge guesses, and drops
// text-body-sm next to text-subtle because it takes both for colours.
import tokens from './token-names.json';

const twMerge = extendTailwindMerge({
  extend: {
    theme: tokens.theme,
    classGroups: { 'border-w': [{ border: tokens.borderWidth }] },
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
