/**
 * # Date Formatting Utilities
 *
 * Utilities for calculating and formatting deadlines in the email verification banner.
 * Matches LiveView's datetime formatting pattern: "Monday, 15 January @ 14:30 UTC"
 */

import { addHours } from 'date-fns';

/**
 * Calculates the deadline for email verification by adding 48 hours to the given timestamp.
 *
 * @param insertedAt - ISO 8601 datetime string of when the user was created
 * @returns Date object representing the deadline (48 hours after insertedAt)
 *
 * @example
 * calculateDeadline("2025-01-13T10:30:00Z") // Returns Date 48 hours later
 */
export function calculateDeadline(insertedAt: string): Date {
  const baseDate = new Date(insertedAt);
  return addHours(baseDate, 48);
}

/**
 * Month names for formatting
 */
const MONTHS = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/**
 * Weekday names for formatting
 */
const WEEKDAYS = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

/**
 * Formats a deadline date to match LiveView's pattern: "Monday, 15 January @ 14:30 UTC"
 *
 * Format breakdown:
 * - Weekday: Full weekday name (e.g., "Monday")
 * - Date: Day of month without leading zero (e.g., "15")
 * - Month: Full month name (e.g., "January")
 * - Time: 24-hour format with leading zeros (e.g., "14:30")
 * - Timezone: Always "UTC"
 *
 * @param deadline - Date object to format
 * @returns Formatted string in LiveView pattern
 *
 * @example
 * formatDeadline(new Date("2025-01-15T14:30:00Z")) // "Wednesday, 15 January @ 14:30 UTC"
 */
export function formatDeadline(deadline: Date): string {
  // Extract UTC components directly to avoid timezone issues
  const weekday = WEEKDAYS[deadline.getUTCDay()];
  const day = deadline.getUTCDate();
  const month = MONTHS[deadline.getUTCMonth()];
  const hours = String(deadline.getUTCHours()).padStart(2, '0');
  const minutes = String(deadline.getUTCMinutes()).padStart(2, '0');

  // Format: "Monday, 15 January @ 14:30 UTC"
  return `${weekday}, ${day} ${month} @ ${hours}:${minutes} UTC`;
}
