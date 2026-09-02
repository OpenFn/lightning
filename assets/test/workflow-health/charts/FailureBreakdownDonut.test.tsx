import { render, screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import { FailureBreakdownDonut } from '#/workflow-health/charts/FailureBreakdownDonut';

import { counts } from './counts';

describe('FailureBreakdownDonut', () => {
  test('lists each failure state with its count and share of failures', () => {
    render(
      <FailureBreakdownDonut
        counts={counts({
          success: 1146,
          failed: 98,
          crashed: 24,
          killed: 12,
          lost: 7,
        })}
        emptyMessage="No failures"
      />
    );

    expect(screen.getByText('failed')).toBeVisible();
    expect(screen.getByText('98')).toBeVisible();
    // 98 of 141 failures — success is excluded from the denominator, so this
    // reads 69.5% and not 7.6% of all work orders.
    expect(screen.getByText('69.5%')).toBeVisible();
    expect(screen.getByText('crashed')).toBeVisible();
    expect(screen.getByText('17.0%')).toBeVisible();
  });

  // A work order the run limit refused never ran, but it is still a failure
  // the project can act on, so it gets its own slice rather than vanishing.
  test('gives rejected work orders a slice of their own', () => {
    render(
      <FailureBreakdownDonut
        counts={counts({ failed: 3, rejected: 1 })}
        emptyMessage="No failures"
      />
    );

    expect(screen.getByText('rejected')).toBeVisible();
    expect(screen.getByText('25.0%')).toBeVisible();
  });

  test('omits states that never happened', () => {
    render(
      <FailureBreakdownDonut
        counts={counts({ failed: 3 })}
        emptyMessage="No failures"
      />
    );

    expect(screen.getByText('failed')).toBeVisible();
    expect(screen.queryByText('killed')).not.toBeInTheDocument();
    expect(screen.queryByText('exception')).not.toBeInTheDocument();
  });

  // This panel breaks down the Outcomes donut's red wedge, and cancelled is
  // not in it — drawing it here would make the two shares disagree.
  test('never slices cancelled, however many there are', () => {
    render(
      <FailureBreakdownDonut
        counts={counts({ failed: 3, cancelled: 90 })}
        emptyMessage="No failures"
      />
    );

    expect(screen.queryByText('cancelled')).not.toBeInTheDocument();
    // 3 of 3 failures, not 3 of 93.
    expect(screen.getByText('100.0%')).toBeVisible();
  });

  test('is empty when the only other outcome was cancelled', () => {
    render(
      <FailureBreakdownDonut
        counts={counts({ success: 10, cancelled: 5 })}
        emptyMessage="No failures in the last 30 days"
      />
    );

    expect(screen.getByText('No failures in the last 30 days')).toBeVisible();
  });

  test('is empty when every work order succeeded', () => {
    render(
      <FailureBreakdownDonut
        counts={counts({ success: 1146 })}
        emptyMessage="No failures in the last 30 days"
      />
    );

    expect(screen.getByText('No failures in the last 30 days')).toBeVisible();
    expect(screen.queryByText('failed')).not.toBeInTheDocument();
  });
});
