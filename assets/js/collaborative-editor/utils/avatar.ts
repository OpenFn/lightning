/**
 * # Avatar Utilities
 *
 * Utilities for generating avatar initials from user data.
 */

import type { UserContext } from "../types/sessionContext";

/**
 * Generates avatar initials from user data
 *
 * Returns initials in the format: "FirstInitialLastInitial" (e.g., "JD" for "John Doe")
 * Falls back to "??" if user data is incomplete or null
 *
 * @param user - User context data (can be null)
 * @returns Two-character initials string or "??" fallback
 *
 * @example
 * ```typescript
 * getAvatarInitials({ first_name: "John", last_name: "Doe", ... }) // "JD"
 * getAvatarInitials({ first_name: "A", last_name: "B", ... }) // "AB"
 * getAvatarInitials({ first_name: "", last_name: "Doe", ... }) // "??"
 * getAvatarInitials(null) // "??"
 * ```
 */
export function getAvatarInitials(
  user: Pick<UserContext, "first_name" | "last_name"> | null
): string {
  // Handle null user
  if (!user) {
    return "??";
  }

  // Extract first and last name, trimming whitespace
  const firstName = user.first_name.trim();
  const lastName = user.last_name.trim();

  // If either name is empty, return fallback
  if (!firstName || !lastName) {
    return "??";
  }

  // Get first character of each name, uppercase
  const firstInitial = firstName.charAt(0).toUpperCase();
  const lastInitial = lastName.charAt(0).toUpperCase();

  return `${firstInitial}${lastInitial}`;
}

export function splitName(name: string) {
  const nameParts = name.split(/\s+/);
  const firstName = nameParts[0] || "";
  const lastName = nameParts.length > 1 ? nameParts[nameParts.length - 1] : "";

  return {
    first_name: firstName,
    last_name: lastName,
  };
}
