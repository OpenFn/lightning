/**
 * Tests for the `datetime-local` <-> UTC conversion used by date filters.
 *
 * See https://github.com/OpenFn/lightning/issues/4983: a wall-clock time picked
 * in the browser used to be filtered on as if it were UTC.
 */

import { afterAll, beforeAll, describe, expect, test } from 'vitest';

import { localInputToUTC, utcToLocalInput } from '../../js/utils/localDateTime';

const originalTZ = process.env['TZ'];

describe('localDateTime in a UTC+1 timezone', () => {
  // Europe/Berlin is UTC+1 in winter and UTC+2 over summer, which keeps the
  // conversion honest about daylight saving.
  beforeAll(() => {
    process.env['TZ'] = 'Europe/Berlin';
  });

  afterAll(() => {
    process.env['TZ'] = originalTZ;
  });

  describe('localInputToUTC', () => {
    test('reads the picked time as local time', () => {
      expect(localInputToUTC('2026-01-17T16:40')).toBe(
        '2026-01-17T15:40:00.000Z'
      );
    });

    test('uses the offset in effect on the picked date', () => {
      // Same wall clock, but in summer the zone is UTC+2.
      expect(localInputToUTC('2026-07-17T16:40')).toBe(
        '2026-07-17T14:40:00.000Z'
      );
    });

    test('returns null for empty and unparseable values', () => {
      expect(localInputToUTC('')).toBeNull();
      expect(localInputToUTC(null)).toBeNull();
      expect(localInputToUTC(undefined)).toBeNull();
      expect(localInputToUTC('not a date')).toBeNull();
    });
  });

  describe('utcToLocalInput', () => {
    test('renders a UTC timestamp as local wall-clock time', () => {
      expect(utcToLocalInput('2026-01-17T15:40:00Z')).toBe('2026-01-17T16:40');
    });

    test('accepts the timestamp formats the server renders', () => {
      expect(utcToLocalInput('2026-01-17T15:40:00.123456Z')).toBe(
        '2026-01-17T16:40'
      );
      expect(utcToLocalInput('2026-01-17 15:40:00.123456Z')).toBe(
        '2026-01-17T16:40'
      );
    });

    test('returns an empty value for empty and unparseable timestamps', () => {
      expect(utcToLocalInput('')).toBe('');
      expect(utcToLocalInput(null)).toBe('');
      expect(utcToLocalInput(undefined)).toBe('');
      expect(utcToLocalInput('not a date')).toBe('');
    });
  });

  test('round-trips a picked time', () => {
    expect(utcToLocalInput(localInputToUTC('2026-07-17T16:40'))).toBe(
      '2026-07-17T16:40'
    );
  });
});
