/**
 * User Color Utility
 *
 * Generates consistent, deterministic colors for users in collaborative editing.
 * Same user ID will always get the same color.
 */

export const USER_COLORS = [
  '#E53935', // red
  '#8E24AA', // purple
  '#00ACC1', // cyan
  '#43A047', // green
  '#FB8C00', // orange
  '#3949AB', // indigo
  '#D81B60', // magenta
  '#6D4C41', // brown
];

/**
 * Generate a consistent color for a user based on their ID
 * Uses a simple hash function to map user ID to color palette
 */
export function generateUserColor(userId: string): string {
  const index = hashToIndex(userId, USER_COLORS.length);
  return USER_COLORS[index];
}

// FNV-1a with a slight twist.
function hashToIndex(userId: string, paletteLength: number) {
  const str = userId.replace(/-/g, '').toLowerCase();
  let hash = 2166136261;
  for (let i = 0; i < str.length; i++) {
    hash ^= str.charCodeAt(i);
    hash = Math.imul(hash, 16777619) >>> 0;
  }
  hash ^= hash >> 16; // twist
  return Math.abs(hash) % paletteLength;
}
