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
          bucket('2026-09-09T00:00:00Z', {
            success: 60,
            killed: 1,
            exception: 1,
            lost: 1,
            cancelled: 4,
          }),
        ]}
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
          bucket('2026-09-09T00:00:00Z'),
        ]}
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
          bucket('2026-09-09T00:00:00Z'),
        ]}
        emptyMessage="No runs in the last 30 days"
      />
    );

    expect(screen.getByText('No runs in the last 30 days')).toBeVisible();
    expect(screen.queryByText('Failed')).not.toBeInTheDocument();
  });
});

// Measured off the gap between the first two buckets, so the meta line follows
// the bars rather than the range the reader picked.
describe('bucketMeta', () => {
  test('names the bucket width the server actually sent', () => {
    const hourly = (hours: number) => [
      bucket('2026-09-09T00:00:00Z'),
      bucket(
        new Date(
          Date.parse('2026-09-09T00:00:00Z') + hours * 3_600_000
        ).toISOString()
      ),
    ];

    expect(bucketMeta(hourly(2))).toBe('2-hour bucket (runs) · UTC');
    expect(bucketMeta(hourly(12))).toBe('12-hour bucket (runs) · UTC');
    expect(bucketMeta(hourly(24))).toBe('daily buckets (runs) · UTC');
  });

  // One bucket has no width to disagree with, so a coarser label is the worst
  // this can cost.
  test('falls back to daily when there is nothing to measure', () => {
    expect(bucketMeta([bucket('2026-09-09T00:00:00Z')])).toBe(
      'daily buckets (runs) · UTC'
    );
  });
});

// The axis names where a bucket starts; the tooltip names the whole slot. The
// day part is left to the locale, so only the clock is asserted literally.
describe('tickLabel and rangeLabel', () => {
  const at = '2026-09-09T14:00:00Z';
  const day = tickLabel(at, 24);

  test('clocks the narrow buckets and dates the wide ones', () => {
    expect(tickLabel(at, 2)).toBe('14:00');
    expect(day).not.toBe('');
  });

  // The date names where a day starts, so it goes on the morning bar and the
  // afternoon is left blank — a date under the afternoon bar would put the
  // day's start half a day late.
  test('dates a half-day bucket on its morning bar only', () => {
    expect(tickLabel('2026-09-09T00:00:00Z', 12)).toBe(day);
    expect(tickLabel(at, 12)).toBe('');
  });

  test('gives the tooltip the whole slot, in UTC', () => {
    expect(rangeLabel(at, 24)).toBe(`${day} UTC`);
    expect(rangeLabel(at, 2)).toBe(`${day}, 14:00 – 16:00 UTC`);
  });
});
