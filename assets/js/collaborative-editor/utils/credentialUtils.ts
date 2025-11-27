/**
 * Utility functions for credential formatting and display
 */

/**
 * Gets the appropriate Tailwind CSS classes for an environment badge
 * @param tag - Environment tag string (e.g., "PRODUCTION", "Staging")
 * @returns Tailwind CSS classes for badge styling
 * @example
 * getEnvironmentBadgeColor("PRODUCTION") → "bg-yellow-100 text-yellow-800"
 * getEnvironmentBadgeColor("staging") → "bg-green-100 text-green-800"
 */
export function getEnvironmentBadgeColor(tag: string): string {
  const lowerTag = tag.toLowerCase();

  if (lowerTag.includes('prod')) {
    return 'bg-yellow-100 text-yellow-800';
  }
  if (lowerTag.includes('staging')) {
    return 'bg-green-100 text-green-800';
  }
  if (lowerTag.includes('dev')) {
    return 'bg-blue-100 text-blue-800';
  }

  return 'bg-gray-100 text-gray-800';
}
