import { render, screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import { OutcomesDonut } from '#/workflow-health/charts/OutcomesDonut';

describe('OutcomesDonut', () => {
  test('labels each completed outcome with its count', () => {
    render(
      <OutcomesDonut
        counts={{ success: 1211, failed: 61 }}
        emptyMessage="No work orders"
      />
    );

    expect(screen.getByText('Success 1,211')).toBeVisible();
    expect(screen.getByText('Failed 61')).toBeVisible();
  });

  test('gives pending neither a slice nor a legend entry', () => {
    render(
      <OutcomesDonut
        counts={{ success: 1211, failed: 61, pending: 12 }}
        emptyMessage="No work orders"
      />
    );

    expect(screen.queryByText(/Pending/)).not.toBeInTheDocument();
  });

  test('is empty when only pending work orders exist', () => {
    // Also pins that pending is out of the total: were it counted, this would
    // render a donut instead of the empty message.
    render(
      <OutcomesDonut
        counts={{ success: 0, failed: 0, pending: 12 }}
        emptyMessage="No completed work orders in the last 30 days"
      />
    );

    expect(
      screen.getByText('No completed work orders in the last 30 days')
    ).toBeVisible();
    expect(screen.queryByText(/Success/)).not.toBeInTheDocument();
  });
});
