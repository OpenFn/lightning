import { render, screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import { OutcomesDonut } from '#/workflow-health/charts/OutcomesDonut';

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
        })}
        emptyMessage="No runs"
      />
    );

    expect(screen.getByText('Success')).toBeVisible();
    expect(screen.getByText('1,146')).toBeVisible();
    // 98 + 24 + 12 + 7, and 141 of 1,287 runs.
    expect(screen.getByText('Failed')).toBeVisible();
    expect(screen.getByText('141')).toBeVisible();
    expect(screen.getByText('11.0%')).toBeVisible();
  });

  test('gives pending neither a slice nor a legend entry', () => {
    render(
      <OutcomesDonut
        counts={counts({ success: 1146, failed: 98 })}
        emptyMessage="No runs"
      />
    );

    expect(screen.queryByText(/[Pp]ending/)).not.toBeInTheDocument();
  });

  test('shows the empty message rather than a donut of zeroes', () => {
    render(
      <OutcomesDonut
        counts={counts()}
        emptyMessage="No finished runs in the last 30 days"
      />
    );

    expect(
      screen.getByText('No finished runs in the last 30 days')
    ).toBeVisible();
    expect(screen.queryByText('Success')).not.toBeInTheDocument();
  });
});
