import { render, screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import { OutcomesDonut } from '#/health/charts/OutcomesDonut';

import { counts } from './counts';

describe('OutcomesDonut', () => {
  test('folds every failure state into one Failed slice', () => {
    render(
      <OutcomesDonut
        counts={counts({
          success: 1146,
          failed: 98,
          crashed: 24,
          killed: 12,
          lost: 7,
          rejected: 3,
        })}
        emptyMessage="No work orders"
      />
    );

    expect(screen.getByText('Success')).toBeVisible();
    expect(screen.getByText('1,146')).toBeVisible();
    // 98 + 24 + 12 + 7 + 3, and 144 of 1,290 work orders — rejected lands in
    // this wedge for free, because it is in `FAILURE_STATES`.
    expect(screen.getByText('Failed')).toBeVisible();
    expect(screen.getByText('144')).toBeVisible();
    expect(screen.getByText('11.2%')).toBeVisible();
  });

  // Stopping a work order on purpose is not a failure to drive down, so it sits
  // outside the red wedge — but it is still a finished outcome, so the totals
  // only add up if this panel draws it.
  test('draws cancelled as its own slice, outside the Failed wedge', () => {
    render(
      <OutcomesDonut
        counts={counts({ success: 80, failed: 10, cancelled: 10 })}
        emptyMessage="No work orders"
      />
    );

    expect(screen.getByText('Cancelled')).toBeVisible();
    // Failed is 10, not 20: cancelled is not folded in. Both read 10.0% of 100.
    expect(screen.getAllByText('10')).toHaveLength(2);
    expect(screen.getAllByText('10.0%')).toHaveLength(2);
  });

  test('leaves the cancelled row out when nothing was cancelled', () => {
    render(
      <OutcomesDonut
        counts={counts({ success: 80, failed: 10 })}
        emptyMessage="No work orders"
      />
    );

    expect(screen.queryByText('Cancelled')).not.toBeInTheDocument();
    // Failed still shows at zero — that is the answer someone came for.
    expect(screen.getByText('Failed')).toBeVisible();
  });

  test('gives pending neither a slice nor a legend entry', () => {
    render(
      <OutcomesDonut
        counts={counts({ success: 1146, failed: 98 })}
        emptyMessage="No work orders"
      />
    );

    expect(screen.queryByText(/[Pp]ending/)).not.toBeInTheDocument();
  });

  test('shows the empty message rather than a donut of zeroes', () => {
    render(
      <OutcomesDonut
        counts={counts()}
        emptyMessage="No finished work orders in the last 30 days"
      />
    );

    expect(
      screen.getByText('No finished work orders in the last 30 days')
    ).toBeVisible();
    expect(screen.queryByText('Success')).not.toBeInTheDocument();
  });
});
