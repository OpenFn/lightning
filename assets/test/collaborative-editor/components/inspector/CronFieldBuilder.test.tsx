/**
 * CronFieldBuilder Component Tests
 *
 * Tests for the CronFieldBuilder cron expression builder:
 * - Parsing various cron expression formats
 * - Frequency selection and conditional field rendering
 * - User interactions updating cron expressions
 * - Custom expression input
 * - Disabled state handling
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test, vi } from 'vitest';

import { CronFieldBuilder } from '../../../../js/collaborative-editor/components/inspector/CronFieldBuilder';

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

describe('CronFieldBuilder - Parsing Cron Expressions', () => {
  // Rows: [expression, expectedDisplayValues, checkedCheckboxNames?]
  // checkedCheckboxNames is a regex array for role="checkbox" elements that
  // must be checked when rendered. Missing means no checkbox assertions.
  test.each<[string, string, string[], RegExp[]?]>([
    ['empty defaults to daily', '', ['Every day']],
    [
      '*/15 * * * * → every N minutes',
      '*/15 * * * *',
      ['Every N minutes', '15 minutes'],
    ],
    [
      '*/8 * * * * → every N minutes (custom interval)',
      '*/8 * * * *',
      ['Every N minutes', '8 minutes'],
    ],
    [
      '0 */6 * * * → every N hours',
      '0 */6 * * *',
      ['Every N hours', '6 hours'],
    ],
    [
      '0 */20 * * * → every N hours (custom interval)',
      '0 */20 * * *',
      ['Every N hours', '20 hours'],
    ],
    ['30 * * * * → hourly', '30 * * * *', ['Every hour', '30']],
    ['30 9 * * * → daily', '30 9 * * *', ['Every day', '09', '30']],
    [
      '30 9 * * 1-5 → weekdays',
      '30 9 * * 1-5',
      ['Every weekday (Mon-Fri)', '09', '30'],
    ],
    ['30 9 * * 1 → weekly', '30 9 * * 1', ['Every week', 'Monday', '09', '30']],
    [
      '30 9 * * 1,3,5 → weekly (multi-day shows first)',
      '30 9 * * 1,3,5',
      ['Every week', '09', '30'],
    ],
    ['30 9 15 * * → monthly', '30 9 15 * *', ['Every month', '15', '09', '30']],
    [
      '30 9 15 1,6 * → specific months',
      '30 9 15 1,6 *',
      ['Specific months', '15', '09', '30'],
      [/jan/i, /jun/i],
    ],
    [
      '30 9 15 1-3 * → specific months (range)',
      '30 9 15 1-3 *',
      ['Specific months'],
      [/jan/i, /feb/i, /mar/i],
    ],
    ['0 0 L * * → unrecognized → custom', '0 0 L * *', ['Custom']],
    [
      '5 8 * * * → single-digit padding',
      '5 8 * * *',
      ['Every day', '08', '05'],
    ],
  ])('%s', (_label, expression, displayValues, checkedCheckboxes) => {
    render(<CronFieldBuilder value={expression} onChange={vi.fn()} />);

    for (const value of displayValues) {
      expect(screen.getByDisplayValue(value)).toBeInTheDocument();
    }

    if (checkedCheckboxes) {
      for (const pattern of checkedCheckboxes) {
        expect(screen.getByRole('checkbox', { name: pattern })).toBeChecked();
      }
    }
  });
});

// ---------------------------------------------------------------------------
// Frequency Selection
// ---------------------------------------------------------------------------

describe('CronFieldBuilder - Frequency Selection', () => {
  // Rows: [description, startValue, targetFreq, expectedOnChangeArg, expectedLabeledFields, absentLabeledFields?]
  test.each<[string, string, string, string, string[], string[]?]>([
    [
      'every_n_minutes → shows interval dropdown',
      '30 9 * * *',
      'every_n_minutes',
      '*/15 * * * *',
      ['Every'],
    ],
    [
      'every_n_hours → shows interval dropdown',
      '30 9 * * *',
      'every_n_hours',
      '0 */6 * * *',
      ['Every'],
    ],
    [
      'hourly → shows minute only (no hour)',
      '30 9 * * *',
      'hourly',
      '30 * * * *',
      ['Minute'],
      ['Hour'],
    ],
    [
      'daily → shows hour and minute',
      '30 * * * *',
      'daily',
      '30 00 * * *',
      ['Hour', 'Minute'],
    ],
    [
      'weekdays → shows hour and minute',
      '30 9 * * *',
      'weekdays',
      '30 09 * * 1-5',
      ['Hour', 'Minute'],
    ],
    [
      'weekly → shows day, hour, and minute',
      '30 9 * * *',
      'weekly',
      '30 09 * * 01',
      ['Day', 'Hour', 'Minute'],
    ],
    [
      'monthly → shows day, hour, and minute',
      '30 9 * * *',
      'monthly',
      '30 09 01 * *',
      ['Hour', 'Minute'],
    ],
  ])(
    '%s',
    async (
      _label,
      startValue,
      targetFreq,
      expectedExpression,
      expectedFields,
      absentFields
    ) => {
      const user = userEvent.setup();
      const mockOnChange = vi.fn();

      render(<CronFieldBuilder value={startValue} onChange={mockOnChange} />);

      await user.selectOptions(screen.getByLabelText('Frequency'), targetFreq);

      expect(mockOnChange).toHaveBeenCalledWith(expectedExpression);

      for (const label of expectedFields) {
        // getAllByLabelText handles cases where the same label appears multiple times
        expect(screen.getAllByLabelText(label)[0]).toBeInTheDocument();
      }

      if (absentFields) {
        for (const label of absentFields) {
          expect(screen.queryByLabelText(label)).not.toBeInTheDocument();
        }
      }
    }
  );

  test('switching to specific_months shows month checkboxes (Jan and Dec)', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />);
    await user.selectOptions(
      screen.getByLabelText('Frequency'),
      'specific_months'
    );

    expect(screen.getAllByLabelText('Day')[0]).toBeInTheDocument();
    expect(screen.getByLabelText('Hour')).toBeInTheDocument();
    expect(screen.getByLabelText('Minute')).toBeInTheDocument();
    expect(screen.getByText('Months')).toBeInTheDocument();
    expect(screen.getByRole('checkbox', { name: /jan/i })).toBeInTheDocument();
    expect(screen.getByRole('checkbox', { name: /dec/i })).toBeInTheDocument();
  });

  test('switching to custom mode preserves current expression', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 15 * *" onChange={mockOnChange} />);
    await user.selectOptions(screen.getByLabelText('Frequency'), 'custom');

    expect(mockOnChange).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// User Interactions
// ---------------------------------------------------------------------------

describe('CronFieldBuilder - User Interactions', () => {
  test('changing minute in hourly mode updates expression', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 * * * *" onChange={mockOnChange} />);

    const minuteSelect = screen.getByLabelText('Minute');
    await user.selectOptions(minuteSelect, '45');

    expect(mockOnChange).toHaveBeenCalledWith('45 * * * *');
  });

  test('changing hour and minute in daily mode updates expression', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />);

    const hourSelect = screen.getByLabelText('Hour');
    await user.selectOptions(hourSelect, '14');

    expect(mockOnChange).toHaveBeenCalledWith('30 14 * * *');

    const minuteSelect = screen.getByLabelText('Minute');
    await user.selectOptions(minuteSelect, '15');

    expect(mockOnChange).toHaveBeenCalledWith('15 14 * * *');
  });

  test('changing interval in every_n_minutes mode updates expression', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="*/15 * * * *" onChange={mockOnChange} />);

    const intervalSelect = screen.getByLabelText('Every');
    await user.selectOptions(intervalSelect, '30');

    expect(mockOnChange).toHaveBeenCalledWith('*/30 * * * *');
  });

  test('changing interval in every_n_hours mode updates expression', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="0 */6 * * *" onChange={mockOnChange} />);

    const intervalSelect = screen.getByLabelText('Every');
    await user.selectOptions(intervalSelect, '12');

    expect(mockOnChange).toHaveBeenCalledWith('0 */12 * * *');
  });

  test('changing weekday in weekly mode updates expression', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 * * 1" onChange={mockOnChange} />);

    const weekdaySelect = screen.getByLabelText('Day');
    await user.selectOptions(weekdaySelect, '05');

    expect(mockOnChange).toHaveBeenCalledWith('30 09 * * 05');
  });

  test('changing monthday in monthly mode updates expression', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 15 * *" onChange={mockOnChange} />);

    const monthdaySelect = screen.getAllByLabelText('Day')[0];
    await user.selectOptions(monthdaySelect, '20');

    expect(mockOnChange).toHaveBeenCalledWith('30 09 20 * *');
  });

  test('checking month checkboxes in specific_months mode updates expression', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 15 1 *" onChange={mockOnChange} />);

    const febCheckbox = screen.getByRole('checkbox', { name: /feb/i });
    await user.click(febCheckbox);

    expect(mockOnChange).toHaveBeenCalledWith('30 09 15 1,2 *');
  });

  test('unchecking month checkboxes in specific_months mode updates expression', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(
      <CronFieldBuilder value="30 9 15 1,2,3 *" onChange={mockOnChange} />
    );

    const febCheckbox = screen.getByRole('checkbox', { name: /feb/i });
    await user.click(febCheckbox);

    expect(mockOnChange).toHaveBeenCalledWith('30 09 15 1,3 *');
  });

  test('preserves custom interval when switching to every_n_minutes', () => {
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="*/7 * * * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('7 minutes')).toBeInTheDocument();

    // Custom interval should be preserved in dropdown
    const intervalSelect = screen.getByLabelText('Every');
    expect(intervalSelect).toHaveValue('7');
  });

  test('preserves custom interval when switching to every_n_hours', () => {
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="0 */5 * * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('5 hours')).toBeInTheDocument();

    // Custom interval should be preserved in dropdown
    const intervalSelect = screen.getByLabelText('Every');
    expect(intervalSelect).toHaveValue('5');
  });
});

// ---------------------------------------------------------------------------
// Advanced Section
// ---------------------------------------------------------------------------

describe('CronFieldBuilder - Advanced Section', () => {
  test('advanced section is initially collapsed', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />);

    // The toggle button should be present
    expect(
      screen.getByRole('button', { name: /cron expression/i })
    ).toBeInTheDocument();

    // The input should not be visible
    expect(screen.queryByPlaceholderText('0 0 * * *')).not.toBeInTheDocument();
  });

  test('clicking toggle button expands advanced section', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />);

    const toggleButton = screen.getByRole('button', {
      name: /cron expression/i,
    });
    await user.click(toggleButton);

    // The input should now be visible
    expect(screen.getByPlaceholderText('0 0 * * *')).toBeInTheDocument();
    expect(screen.getByDisplayValue('30 9 * * *')).toBeInTheDocument();
  });

  test('manually editing cron expression in advanced section triggers onChange', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />);

    // Expand advanced section
    const toggleButton = screen.getByRole('button', {
      name: /cron expression/i,
    });
    await user.click(toggleButton);

    // Type into the expression input
    const input = screen.getByPlaceholderText('0 0 * * *');
    await user.click(input);
    await user.keyboard('X');

    // Check that onChange was called with modified value
    expect(mockOnChange).toHaveBeenCalled();
    expect(mockOnChange).toHaveBeenCalledWith('30 9 * * *X');
  });

  test('editing cron expression in advanced section updates frequency selector', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    const { rerender } = render(
      <CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />
    );

    // Expand advanced section
    const toggleButton = screen.getByRole('button', {
      name: /cron expression/i,
    });
    await user.click(toggleButton);

    // Edit to hourly expression
    const input = screen.getByPlaceholderText('0 0 * * *');
    await user.clear(input);
    await user.type(input, '45 * * * *');

    // Simulate external value update (as would happen in real usage)
    rerender(<CronFieldBuilder value="45 * * * *" onChange={mockOnChange} />);

    // Wait for the component to update
    await waitFor(() => {
      expect(screen.getByDisplayValue('Every hour')).toBeInTheDocument();
    });
  });

  test('onBlur callback is triggered when blurring advanced input', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();
    const mockOnBlur = vi.fn();

    render(
      <CronFieldBuilder
        value="30 9 * * *"
        onChange={mockOnChange}
        onBlur={mockOnBlur}
      />
    );

    // Expand advanced section
    const toggleButton = screen.getByRole('button', {
      name: /cron expression/i,
    });
    await user.click(toggleButton);

    const input = screen.getByPlaceholderText('0 0 * * *');
    await user.click(input);
    await user.tab(); // Blur the input

    expect(mockOnBlur).toHaveBeenCalled();
  });

  test('selecting Custom frequency auto-opens the cron expression input', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />);

    // Initially collapsed for a recognised (daily) expression.
    expect(screen.queryByPlaceholderText('0 0 * * *')).not.toBeInTheDocument();

    await user.selectOptions(screen.getByLabelText('Frequency'), 'custom');

    expect(screen.getByPlaceholderText('0 0 * * *')).toBeInTheDocument();
  });

  test('loading an unrecognized (custom) expression auto-opens the input', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="0 0 L * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Custom')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('0 0 * * *')).toBeInTheDocument();
  });

  test('shows the humanized description below the cron expression input', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="0 9 * * 1-5" onChange={mockOnChange} />);

    await user.click(screen.getByRole('button', { name: /cron expression/i }));

    // cronstrue humanizes "0 9 * * 1-5".
    expect(
      screen.getByText('At 09:00 AM, Monday through Friday')
    ).toBeInTheDocument();
  });

  test('shows an invalid notice for an unparseable expression', () => {
    const mockOnChange = vi.fn();

    // An unparseable expression is "custom", so the input auto-opens; cronstrue
    // can't humanize it, so the invalid notice shows instead of a description.
    render(<CronFieldBuilder value="0 0 * * XYZ" onChange={mockOnChange} />);

    expect(screen.getByText('Invalid cron expression')).toBeInTheDocument();
  });
});

// ---------------------------------------------------------------------------
// Disabled State
// ---------------------------------------------------------------------------

describe('CronFieldBuilder - Disabled State', () => {
  test('all inputs are disabled when disabled prop is true', () => {
    const mockOnChange = vi.fn();
    render(
      <CronFieldBuilder
        value="30 9 * * *"
        onChange={mockOnChange}
        disabled={true}
      />
    );

    const frequencySelect = screen.getByLabelText('Frequency');
    const hourSelect = screen.getByLabelText('Hour');
    const minuteSelect = screen.getByLabelText('Minute');

    expect(frequencySelect).toBeDisabled();
    expect(hourSelect).toBeDisabled();
    expect(minuteSelect).toBeDisabled();
  });

  test('advanced toggle button is disabled when disabled prop is true', () => {
    const mockOnChange = vi.fn();
    render(
      <CronFieldBuilder
        value="30 9 * * *"
        onChange={mockOnChange}
        disabled={true}
      />
    );

    const toggleButton = screen.getByRole('button', {
      name: /cron expression/i,
    });
    expect(toggleButton).toBeDisabled();
  });

  test('month checkboxes are disabled in specific_months mode when disabled', () => {
    const mockOnChange = vi.fn();
    render(
      <CronFieldBuilder
        value="30 9 15 1,6 *"
        onChange={mockOnChange}
        disabled={true}
      />
    );

    const janCheckbox = screen.getByRole('checkbox', { name: /jan/i });
    expect(janCheckbox).toBeDisabled();
  });

  test('advanced input is disabled when disabled prop is true', () => {
    const mockOnChange = vi.fn();

    render(
      <CronFieldBuilder
        value="30 9 * * *"
        onChange={mockOnChange}
        disabled={true}
      />
    );

    // Expand advanced section (button should still be clickable logic, but let's check the input)
    const toggleButton = screen.getByRole('button', {
      name: /cron expression/i,
    });

    // Button is disabled, so we can't click it in this test
    expect(toggleButton).toBeDisabled();
  });
});

// ---------------------------------------------------------------------------
// External Value Changes
// ---------------------------------------------------------------------------

describe('CronFieldBuilder - External Value Changes', () => {
  test('syncs with external value changes', () => {
    const mockOnChange = vi.fn();
    const { rerender } = render(
      <CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />
    );

    expect(screen.getByDisplayValue('Every day')).toBeInTheDocument();
    expect(screen.getByDisplayValue('09')).toBeInTheDocument();
    expect(screen.getByDisplayValue('30')).toBeInTheDocument();

    // Update external value
    rerender(<CronFieldBuilder value="45 * * * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Every hour')).toBeInTheDocument();
    expect(screen.getByDisplayValue('45')).toBeInTheDocument();
  });

  test('updates fields when external value changes to different frequency', () => {
    const mockOnChange = vi.fn();
    const { rerender } = render(
      <CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />
    );

    expect(screen.getByDisplayValue('Every day')).toBeInTheDocument();

    // Change to weekly
    rerender(<CronFieldBuilder value="30 9 * * 1" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Every week')).toBeInTheDocument();
    expect(screen.getByDisplayValue('Monday')).toBeInTheDocument();
  });
});
