/**
 * User Color Utility
 *
 * Generates consistent, deterministic colors for users in collaborative editing.
 * Same user ID will always get the same color.
 */

const USER_COLORS = [
  "#FF6B6B",
  "#4ECDC4",
  "#45B7D1",
  "#FFA07A",
  "#98D8C8",
  "#FFCF56",
  "#FF8B94",
  "#AED581",
];

/**
 * Generate a consistent color for a user based on their ID
 * Uses a simple hash function to map user ID to color palette
 */
export function generateUserColor(userId: string): string {
  const hash = userId.split("").reduce((a, b) => {
    a = (a << 5) - a + b.charCodeAt(0);
    return a & a;
  }, 0);

  return USER_COLORS[Math.abs(hash) % USER_COLORS.length] || "#999999";
}
