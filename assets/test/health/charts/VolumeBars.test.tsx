import { render, screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import {
  bucketMeta,
  rangeLabel,
  tickLabel,
  VolumeBars,
} from '#/health/charts/VolumeBars';

import { bucket } from './counts';

describe('VolumeBars', () => {
  test('folds every run failure state into one Failed total', () => {
    render(
      <VolumeBars
        buckets={[
          bucket('2026-09-08T00:00:00Z', {
            success: 40,
            failed: 3,
            crashed: 2,
          }),
          bucket('2026-09-08T01:00:00Z', {
            success: 60,
            killed: 1,
            exception: 1,
            lost: 1,
            cancelled: 4,
          }),
        ]}
        timezone="Etc/UTC"
        hours={2}
        emptyMessage="No runs"
      />
    );

    // 3 + 2 + 1 + 1 + 1 across both buckets.
    expect(
      screen.getByText('Window totals: Success 100, Cancelled 4, Failed 8.')
    ).toBeInTheDocument();

    // The visible legend is a key only; the counts are on the y-axis.
    expect(screen.getByText('Success')).toBeVisible();
    expect(screen.getByText('Cancelled')).toBeVisible();
    expect(screen.getByText('Failed')).toBeVisible();
  });

  // Stopping a run on purpose is not a failure, so it keeps its own segment.
  test('keeps cancelled out of the Failed total', () => {
    render(
      <VolumeBars
        buckets={[
          bucket('2026-09-08T00:00:00Z', { failed: 2, cancelled: 5 }),
          bucket('2026-09-08T01:00:00Z'),
        ]}
        timezone="Etc/UTC"
        hours={2}
        emptyMessage="No runs"
      />
    );

    expect(
      screen.getByText('Window totals: Success 0, Cancelled 5, Failed 2.')
    ).toBeInTheDocument();
  });

  // The server zero-fills, so a quiet workflow arrives as a full list of
  // nothing — and Recharts would draw a bare axis for it.
  test('shows the empty message when no run landed in the window', () => {
    render(
      <VolumeBars
        buckets={[
          bucket('2026-09-08T00:00:00Z'),
          bucket('2026-09-08T01:00:00Z'),
        ]}
        timezone="Etc/UTC"
        hours={2}
        emptyMessage="No runs in the last 30 days"
      />
    );

    expect(screen.getByText('No runs in the last 30 days')).toBeVisible();
    expect(screen.queryByText('Failed')).not.toBeInTheDocument();
  });
});

// Read off the payload, since the server cuts the grid and names its width.
describe('bucketMeta', () => {
  const volume = (bucket_hours: number) => ({
    window: { from: '2026-09-08T21:00:00Z', to: '2026-09-09T21:00:00Z' },
    timezone: 'Africa/Nairobi',
    bucket_hours,
    buckets: [],
  });

  test('names the bar width and the clock it is cut on', () => {
    expect(bucketMeta(volume(2))).toBe('2-hour buckets · Africa/Nairobi');
    expect(bucketMeta(volume(12))).toBe('12-hour buckets · Africa/Nairobi');
    expect(bucketMeta(volume(24))).toBe('daily buckets · Africa/Nairobi');
  });
});

// The axis names where a bar starts; the tooltip names the whole slot. The day
// part is left to the locale, so only the clock is asserted literally.
describe('tickLabel and rangeLabel', () => {
  const at = '2026-09-09T14:00:00Z';
  const day = tickLabel(at, 24, 'Etc/UTC');

  test('clocks the narrow bars and dates the wide ones', () => {
    expect(tickLabel(at, 2, 'Etc/UTC')).toBe('14:00');
    expect(day).not.toBe('');
  });

  // The date names where a day starts, so it goes on the morning bar and the
  // afternoon is left blank — a date under the afternoon bar would put the
  // day's start half a day late.
  test('dates a half-day bar on its morning bar only', () => {
    expect(tickLabel('2026-09-09T00:00:00Z', 12, 'Etc/UTC')).toBe(day);
    expect(tickLabel(at, 12, 'Etc/UTC')).toBe('');
  });

  test('gives the tooltip the whole slot, with no timezone suffix', () => {
    expect(rangeLabel(at, 24, 'Etc/UTC')).toBe(day);
    expect(rangeLabel(at, 2, 'Etc/UTC')).toBe(`${day}, 14:00 – 16:00`);
  });

  // Closed on the wall clock, not on `start + hours`: the last bar of a local
  // day ends at midnight, and a bar spanning a clock change is 11 or 13 real
  // hours but still 12 on the clock its labels are drawn on.
  test('closes the last bar of a day at midnight', () => {
    const lastBar = '2026-10-25T12:00:00Z';

    expect(rangeLabel('2026-09-09T22:00:00Z', 2, 'Etc/UTC')).toMatch(
      /22:00 – 00:00$/
    );
    expect(rangeLabel(lastBar, 12, 'Europe/London')).toMatch(/12:00 – 00:00$/);
  });

  // A bar opening at 21:00Z is the start of the next day in Nairobi, and it is
  // that date the reader has to see.
  test("dates a bar on the reader's calendar, not on UTC", () => {
    expect(tickLabel('2026-09-08T21:00:00Z', 24, 'Africa/Nairobi')).toBe(
      tickLabel('2026-09-09T00:00:00Z', 24, 'Etc/UTC')
    );
    expect(tickLabel('2026-09-08T21:00:00Z', 12, 'Africa/Nairobi')).toBe(
      tickLabel('2026-09-09T00:00:00Z', 24, 'Etc/UTC')
    );
  });

  // The half- and quarter-hour zones. The grid is floored on the local clock,
  // so a boundary is a local whole hour and no label ever needs minutes.
  test('clocks the off-the-hour zones as whole local hours', () => {
    expect(tickLabel('2026-09-08T18:30:00Z', 2, 'Asia/Kolkata')).toBe('00:00');
    expect(tickLabel('2026-09-08T18:15:00Z', 2, 'Asia/Kathmandu')).toBe(
      '00:00'
    );
  });
});
