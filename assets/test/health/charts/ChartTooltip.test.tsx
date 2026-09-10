import { render, screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import { ChartTooltip } from '#/health/charts/ChartTooltip';

const payload = [
  { dataKey: 'failed', name: 'Failed', value: 7, color: '#d03b3b' },
  { dataKey: 'success', name: 'Success', value: 1, color: '#0ca30c' },
];

describe('ChartTooltip', () => {
  test('draws nothing until a series is hovered', () => {
    const { container } = render(
      <ChartTooltip active={false} payload={payload} />
    );

    expect(container).toBeEmptyDOMElement();
  });

  test("applies the chart's own order, label and value formats", () => {
    render(
      <ChartTooltip
        active
        payload={payload}
        label="2026-09-05T00:00:00Z"
        // The bars are declared in the reverse of the stack, so the panel
        // flips them rather than taking the payload as it comes.
        reverse
        formatLabel={at => `${at} slot`}
        formatValue={value => `${value} runs`}
      />
    );

    expect(screen.getByText('2026-09-05T00:00:00Z slot')).toBeVisible();
    expect(
      screen.getAllByRole('listitem').map(item => item.textContent)
    ).toEqual(['Success1 runs', 'Failed7 runs']);
  });
});
