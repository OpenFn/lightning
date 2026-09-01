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
    // reads 69.5% and not 7.6% of all runs.
    expect(screen.getByText('69.5%')).toBeVisible();
    expect(screen.getByText('crashed')).toBeVisible();
    expect(screen.getByText('17.0%')).toBeVisible();
  });

  test('omits states that never happened', () => {
    render(
      <FailureBreakdownDonut
        counts={counts({ failed: 3 })}
        emptyMessage="No failures"
      />
    );

    expect(screen.getByText('failed')).toBeVisible();
    expect(screen.queryByText('cancelled')).not.toBeInTheDocument();
    expect(screen.queryByText('exception')).not.toBeInTheDocument();
  });

  test('is empty when every run succeeded', () => {
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
