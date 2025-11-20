/**
 * Date Formatting Utilities Tests
 *
 * Comprehensive tests for calculateDeadline and formatDeadline utilities
 * used in the EmailVerificationBanner component.
 */

import { describe, expect, test } from 'vitest';

import {
  calculateDeadline,
  formatDeadline,
} from '../../../js/collaborative-editor/utils/dateFormatting';

// =============================================================================
// CALCULATE DEADLINE TESTS
// =============================================================================

describe.concurrent('calculateDeadline', () => {
  test('adds exactly 48 hours to the inserted_at timestamp', () => {
    const insertedAt = '2025-01-13T10:30:00Z';
    const deadline = calculateDeadline(insertedAt);

    // Expected: 2025-01-15T10:30:00Z (48 hours later)
    expect(deadline.toISOString()).toBe('2025-01-15T10:30:00.000Z');
  });

  test('handles midnight timestamps correctly', () => {
    const insertedAt = '2025-01-13T00:00:00Z';
    const deadline = calculateDeadline(insertedAt);

    expect(deadline.toISOString()).toBe('2025-01-15T00:00:00.000Z');
  });

  test('handles timestamps near end of day', () => {
    const insertedAt = '2025-01-13T23:59:59Z';
    const deadline = calculateDeadline(insertedAt);

    expect(deadline.toISOString()).toBe('2025-01-15T23:59:59.000Z');
  });

  test('handles month transitions correctly', () => {
    // January 30th + 48 hours = February 1st
    const insertedAt = '2025-01-30T12:00:00Z';
    const deadline = calculateDeadline(insertedAt);

    expect(deadline.toISOString()).toBe('2025-02-01T12:00:00.000Z');
  });

  test('handles year transitions correctly', () => {
    // December 30th + 48 hours = January 1st next year
    const insertedAt = '2024-12-30T12:00:00Z';
    const deadline = calculateDeadline(insertedAt);

    expect(deadline.toISOString()).toBe('2025-01-01T12:00:00.000Z');
  });

  test('handles leap year February correctly', () => {
    // February 27th, 2024 (leap year) + 48 hours = February 29th, 2024
    const insertedAt = '2024-02-27T12:00:00Z';
    const deadline = calculateDeadline(insertedAt);

    expect(deadline.toISOString()).toBe('2024-02-29T12:00:00.000Z');
  });

  test('handles non-leap year February correctly', () => {
    // February 27th, 2025 (non-leap year) + 48 hours = February 29th would be March 1st
    const insertedAt = '2025-02-27T12:00:00Z';
    const deadline = calculateDeadline(insertedAt);

    expect(deadline.toISOString()).toBe('2025-03-01T12:00:00.000Z');
  });

  test('handles timestamps with milliseconds', () => {
    const insertedAt = '2025-01-13T10:30:45.123Z';
    const deadline = calculateDeadline(insertedAt);

    // Should preserve milliseconds
    expect(deadline.toISOString()).toBe('2025-01-15T10:30:45.123Z');
  });

  test('handles timestamps in different timezone formats', () => {
    // ISO 8601 allows +00:00 notation as equivalent to Z
    const insertedAt = '2025-01-13T10:30:00+00:00';
    const deadline = calculateDeadline(insertedAt);

    expect(deadline.toISOString()).toBe('2025-01-15T10:30:00.000Z');
  });

  test('handles timestamps with timezone offsets', () => {
    // 10:30 UTC+5 = 05:30 UTC
    const insertedAt = '2025-01-13T10:30:00+05:00';
    const deadline = calculateDeadline(insertedAt);

    // 48 hours later in UTC
    expect(deadline.toISOString()).toBe('2025-01-15T05:30:00.000Z');
  });
});

// =============================================================================
// FORMAT DEADLINE TESTS
// =============================================================================

describe.concurrent('formatDeadline', () => {
  test('formats date in LiveView pattern: "Monday, 15 January @ 14:30 UTC"', () => {
    // Wednesday, January 15th, 2025 at 14:30 UTC
    const deadline = new Date('2025-01-15T14:30:00Z');
    const formatted = formatDeadline(deadline);

    expect(formatted).toBe('Wednesday, 15 January @ 14:30 UTC');
  });

  test('formats day without leading zero for single-digit days', () => {
    // January 5th (single digit)
    const deadline = new Date('2025-01-05T14:30:00Z');
    const formatted = formatDeadline(deadline);

    expect(formatted).toContain('5 January');
    expect(formatted).not.toContain('05 January');
  });

  test('formats day without leading zero for double-digit days', () => {
    // January 15th (double digit)
    const deadline = new Date('2025-01-15T14:30:00Z');
    const formatted = formatDeadline(deadline);

    expect(formatted).toContain('15 January');
  });

  test('formats time with leading zeros for hours', () => {
    // 09:30 should have leading zero
    const deadline = new Date('2025-01-15T09:30:00Z');
    const formatted = formatDeadline(deadline);

    expect(formatted).toContain('@ 09:30 UTC');
  });

  test('formats time with leading zeros for minutes', () => {
    // 14:05 should have leading zero for minutes
    const deadline = new Date('2025-01-15T14:05:00Z');
    const formatted = formatDeadline(deadline);

    expect(formatted).toContain('@ 14:05 UTC');
  });

  test('formats midnight correctly as 00:00', () => {
    const deadline = new Date('2025-01-15T00:00:00Z');
    const formatted = formatDeadline(deadline);

    expect(formatted).toContain('@ 00:00 UTC');
  });

  test('formats 23:59 correctly', () => {
    const deadline = new Date('2025-01-15T23:59:00Z');
    const formatted = formatDeadline(deadline);

    expect(formatted).toContain('@ 23:59 UTC');
  });

  // Test all 12 months are formatted correctly
  test.each([
    { date: '2025-01-15T14:30:00Z', month: 'January' },
    { date: '2025-02-15T14:30:00Z', month: 'February' },
    { date: '2025-03-15T14:30:00Z', month: 'March' },
    { date: '2025-04-15T14:30:00Z', month: 'April' },
    { date: '2025-05-15T14:30:00Z', month: 'May' },
    { date: '2025-06-15T14:30:00Z', month: 'June' },
    { date: '2025-07-15T14:30:00Z', month: 'July' },
    { date: '2025-08-15T14:30:00Z', month: 'August' },
    { date: '2025-09-15T14:30:00Z', month: 'September' },
    { date: '2025-10-15T14:30:00Z', month: 'October' },
    { date: '2025-11-15T14:30:00Z', month: 'November' },
    { date: '2025-12-15T14:30:00Z', month: 'December' },
  ])('formats $month correctly', ({ date, month }) => {
    const deadline = new Date(date);
    const formatted = formatDeadline(deadline);
    expect(formatted).toContain(month);
  });

  // Test all 7 weekdays are formatted correctly
  test.each([
    { date: '2025-01-13T14:30:00Z', weekday: 'Monday' },
    { date: '2025-01-14T14:30:00Z', weekday: 'Tuesday' },
    { date: '2025-01-15T14:30:00Z', weekday: 'Wednesday' },
    { date: '2025-01-16T14:30:00Z', weekday: 'Thursday' },
    { date: '2025-01-17T14:30:00Z', weekday: 'Friday' },
    { date: '2025-01-18T14:30:00Z', weekday: 'Saturday' },
    { date: '2025-01-19T14:30:00Z', weekday: 'Sunday' },
  ])('formats $weekday correctly', ({ date, weekday }) => {
    const deadline = new Date(date);
    const formatted = formatDeadline(deadline);
    expect(formatted).toContain(weekday);
  });

  test('always includes UTC timezone suffix', () => {
    const deadline = new Date('2025-01-15T14:30:00Z');
    const formatted = formatDeadline(deadline);

    expect(formatted).toContain('UTC');
    expect(formatted).toMatch(/UTC$/); // Should end with UTC
  });

  test('formats complete string with all components in correct order', () => {
    const deadline = new Date('2025-01-15T14:30:00Z');
    const formatted = formatDeadline(deadline);

    // Verify complete format pattern
    expect(formatted).toMatch(/^\w+, \d{1,2} \w+ @ \d{2}:\d{2} UTC$/);
  });

  test('handles end of month dates correctly', () => {
    const deadline = new Date('2025-01-31T23:59:00Z');
    const formatted = formatDeadline(deadline);

    expect(formatted).toContain('31 January');
  });

  test('handles leap year dates correctly', () => {
    // February 29th, 2024 (leap year)
    const deadline = new Date('2024-02-29T12:00:00Z');
    const formatted = formatDeadline(deadline);

    expect(formatted).toContain('29 February');
  });
});

// =============================================================================
// INTEGRATION TESTS
// =============================================================================

describe.concurrent('calculateDeadline + formatDeadline integration', () => {
  test('end-to-end: inserted_at to formatted deadline string', () => {
    // User created on Monday, January 13th at 10:30 UTC
    const insertedAt = '2025-01-13T10:30:00Z';

    // Calculate deadline (48 hours later)
    const deadline = calculateDeadline(insertedAt);

    // Format for display
    const formatted = formatDeadline(deadline);

    // Should be Wednesday, January 15th at 10:30 UTC
    expect(formatted).toBe('Wednesday, 15 January @ 10:30 UTC');
  });

  test('end-to-end: user created at midnight', () => {
    const insertedAt = '2025-01-13T00:00:00Z';
    const deadline = calculateDeadline(insertedAt);
    const formatted = formatDeadline(deadline);

    expect(formatted).toBe('Wednesday, 15 January @ 00:00 UTC');
  });

  test('end-to-end: user created just before midnight', () => {
    const insertedAt = '2025-01-13T23:59:00Z';
    const deadline = calculateDeadline(insertedAt);
    const formatted = formatDeadline(deadline);

    expect(formatted).toBe('Wednesday, 15 January @ 23:59 UTC');
  });

  test('end-to-end: deadline crosses month boundary', () => {
    // Created on January 30th at 15:00
    const insertedAt = '2025-01-30T15:00:00Z';
    const deadline = calculateDeadline(insertedAt);
    const formatted = formatDeadline(deadline);

    // 48 hours later: February 1st at 15:00
    expect(formatted).toBe('Saturday, 1 February @ 15:00 UTC');
  });

  test('end-to-end: deadline crosses year boundary', () => {
    // Created on December 30th, 2024 at 15:00
    const insertedAt = '2024-12-30T15:00:00Z';
    const deadline = calculateDeadline(insertedAt);
    const formatted = formatDeadline(deadline);

    // 48 hours later: January 1st, 2025 at 15:00
    expect(formatted).toBe('Wednesday, 1 January @ 15:00 UTC');
  });

  test('end-to-end: leap year February transition', () => {
    // Created on February 27th, 2024 (leap year) at 12:00
    const insertedAt = '2024-02-27T12:00:00Z';
    const deadline = calculateDeadline(insertedAt);
    const formatted = formatDeadline(deadline);

    // 48 hours later: February 29th, 2024 at 12:00
    expect(formatted).toBe('Thursday, 29 February @ 12:00 UTC');
  });

  test('end-to-end: non-leap year February transition', () => {
    // Created on February 27th, 2025 (non-leap year) at 12:00
    const insertedAt = '2025-02-27T12:00:00Z';
    const deadline = calculateDeadline(insertedAt);
    const formatted = formatDeadline(deadline);

    // 48 hours later: March 1st, 2025 at 12:00 (Feb 29 doesn't exist)
    expect(formatted).toBe('Saturday, 1 March @ 12:00 UTC');
  });

  test('end-to-end: handles timezone offset in input', () => {
    // User created at 15:30 in UTC+5 timezone (10:30 UTC)
    const insertedAt = '2025-01-13T15:30:00+05:00';
    const deadline = calculateDeadline(insertedAt);
    const formatted = formatDeadline(deadline);

    // 48 hours later in UTC
    expect(formatted).toBe('Wednesday, 15 January @ 10:30 UTC');
  });

  test('end-to-end: real-world scenario with current-like timestamp', () => {
    // Simulating a user created on October 1st, 2025 at 09:15 UTC
    const insertedAt = '2025-10-01T09:15:00Z';
    const deadline = calculateDeadline(insertedAt);
    const formatted = formatDeadline(deadline);

    // 48 hours later: October 3rd at 09:15 UTC
    expect(formatted).toBe('Friday, 3 October @ 09:15 UTC');
  });
});

// =============================================================================
// EDGE CASE TESTS
// =============================================================================

describe.concurrent('dateFormatting edge cases', () => {
  test('calculateDeadline handles very old timestamps', () => {
    // User from year 2020
    const insertedAt = '2020-01-13T10:30:00Z';
    const deadline = calculateDeadline(insertedAt);

    expect(deadline.toISOString()).toBe('2020-01-15T10:30:00.000Z');
  });

  test('calculateDeadline handles future timestamps', () => {
    // User from year 2030
    const insertedAt = '2030-01-13T10:30:00Z';
    const deadline = calculateDeadline(insertedAt);

    expect(deadline.toISOString()).toBe('2030-01-15T10:30:00.000Z');
  });

  test('formatDeadline handles dates far in the past', () => {
    const deadline = new Date('2000-01-15T14:30:00Z');
    const formatted = formatDeadline(deadline);

    expect(formatted).toContain('January');
    expect(formatted).toContain('15');
    expect(formatted).toContain('UTC');
  });

  test('formatDeadline handles dates far in the future', () => {
    const deadline = new Date('2099-12-31T23:59:00Z');
    const formatted = formatDeadline(deadline);

    expect(formatted).toContain('December');
    expect(formatted).toContain('31');
    expect(formatted).toContain('UTC');
  });
});
