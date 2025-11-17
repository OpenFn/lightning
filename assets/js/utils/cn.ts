import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

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
