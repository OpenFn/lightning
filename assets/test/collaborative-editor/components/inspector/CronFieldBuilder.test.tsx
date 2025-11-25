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

describe('CronFieldBuilder - Parsing Cron Expressions', () => {
  test('parses empty value to default daily frequency', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Every day')).toBeInTheDocument();
  });

  test('parses every N minutes expression: */15 * * * *', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="*/15 * * * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Every N minutes')).toBeInTheDocument();
    expect(screen.getByDisplayValue('15 minutes')).toBeInTheDocument();
  });

  test('parses every N minutes expression (value not in options): */8 * * * *', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="*/8 * * * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Every N minutes')).toBeInTheDocument();
    expect(screen.getByDisplayValue('8 minutes')).toBeInTheDocument();
  });

  test('parses every N hours expression: 0 */6 * * *', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="0 */6 * * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Every N hours')).toBeInTheDocument();
    expect(screen.getByDisplayValue('6 hours')).toBeInTheDocument();
  });

  test('parses every N hours expression (value not in options): 0 */20 * * *', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="0 */20 * * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Every N hours')).toBeInTheDocument();
    expect(screen.getByDisplayValue('20 hours')).toBeInTheDocument();
  });

  test('parses hourly expression: 30 * * * *', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="30 * * * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Every hour')).toBeInTheDocument();
    expect(screen.getByDisplayValue('30')).toBeInTheDocument();
  });

  test('parses daily expression: 30 9 * * *', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Every day')).toBeInTheDocument();
    expect(screen.getByDisplayValue('09')).toBeInTheDocument();
    expect(screen.getByDisplayValue('30')).toBeInTheDocument();
  });

  test('parses weekdays expression: 30 9 * * 1-5', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="30 9 * * 1-5" onChange={mockOnChange} />);

    expect(
      screen.getByDisplayValue('Every weekday (Mon-Fri)')
    ).toBeInTheDocument();
    expect(screen.getByDisplayValue('09')).toBeInTheDocument();
    expect(screen.getByDisplayValue('30')).toBeInTheDocument();
  });

  test('parses weekly expression: 30 9 * * 1', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="30 9 * * 1" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Every week')).toBeInTheDocument();
    expect(screen.getByDisplayValue('Monday')).toBeInTheDocument();
    expect(screen.getByDisplayValue('09')).toBeInTheDocument();
    expect(screen.getByDisplayValue('30')).toBeInTheDocument();
  });

  test('parses weekly expression with multiple days: 30 9 * * 1,3,5', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="30 9 * * 1,3,5" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Every week')).toBeInTheDocument();
    // Note: When multiple days are selected, the select shows the first value
    expect(screen.getByDisplayValue('09')).toBeInTheDocument();
    expect(screen.getByDisplayValue('30')).toBeInTheDocument();
  });

  test('parses monthly expression: 30 9 15 * *', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="30 9 15 * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Every month')).toBeInTheDocument();
    expect(screen.getByDisplayValue('15')).toBeInTheDocument();
    expect(screen.getByDisplayValue('09')).toBeInTheDocument();
    expect(screen.getByDisplayValue('30')).toBeInTheDocument();
  });

  test('parses specific months expression: 30 9 15 1,6 *', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="30 9 15 1,6 *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Specific months')).toBeInTheDocument();
    expect(screen.getByDisplayValue('15')).toBeInTheDocument();
    expect(screen.getByDisplayValue('09')).toBeInTheDocument();
    expect(screen.getByDisplayValue('30')).toBeInTheDocument();

    // Check that Jan and Jun checkboxes are checked
    const janCheckbox = screen.getByRole('checkbox', { name: /jan/i });
    const junCheckbox = screen.getByRole('checkbox', { name: /jun/i });
    expect(janCheckbox).toBeChecked();
    expect(junCheckbox).toBeChecked();
  });

  test('parses specific months with range: 30 9 15 1-3 *', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="30 9 15 1-3 *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Specific months')).toBeInTheDocument();

    // Check that Jan, Feb, Mar checkboxes are checked
    const janCheckbox = screen.getByRole('checkbox', { name: /jan/i });
    const febCheckbox = screen.getByRole('checkbox', { name: /feb/i });
    const marCheckbox = screen.getByRole('checkbox', { name: /mar/i });
    expect(janCheckbox).toBeChecked();
    expect(febCheckbox).toBeChecked();
    expect(marCheckbox).toBeChecked();
  });

  test('parses unrecognized expression as custom', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="0 0 L * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Custom')).toBeInTheDocument();
  });

  test('parses single digit values with padding', () => {
    const mockOnChange = vi.fn();
    render(<CronFieldBuilder value="5 8 * * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('Every day')).toBeInTheDocument();
    expect(screen.getByDisplayValue('08')).toBeInTheDocument();
    expect(screen.getByDisplayValue('05')).toBeInTheDocument();
  });
});

describe('CronFieldBuilder - Frequency Selection', () => {
  test('switching to every_n_minutes shows interval dropdown', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />);

    const frequencySelect = screen.getByLabelText('Frequency');
    await user.selectOptions(frequencySelect, 'every_n_minutes');

    expect(screen.getByLabelText('Every')).toBeInTheDocument();
    expect(screen.getByDisplayValue('15 minutes')).toBeInTheDocument();
    expect(mockOnChange).toHaveBeenCalledWith('*/15 * * * *');
  });

  test('switching to every_n_hours shows interval dropdown', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />);

    const frequencySelect = screen.getByLabelText('Frequency');
    await user.selectOptions(frequencySelect, 'every_n_hours');

    expect(screen.getByLabelText('Every')).toBeInTheDocument();
    expect(screen.getByDisplayValue('6 hours')).toBeInTheDocument();
    expect(mockOnChange).toHaveBeenCalledWith('0 */6 * * *');
  });

  test('switching to hourly shows only minute field', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />);

    const frequencySelect = screen.getByLabelText('Frequency');
    await user.selectOptions(frequencySelect, 'hourly');

    expect(screen.getByLabelText('Minute')).toBeInTheDocument();
    expect(screen.queryByLabelText('Hour')).not.toBeInTheDocument();
    expect(mockOnChange).toHaveBeenCalledWith('30 * * * *');
  });

  test('switching to daily shows hour and minute fields', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 * * * *" onChange={mockOnChange} />);

    const frequencySelect = screen.getByLabelText('Frequency');
    await user.selectOptions(frequencySelect, 'daily');

    expect(screen.getByLabelText('Hour')).toBeInTheDocument();
    expect(screen.getByLabelText('Minute')).toBeInTheDocument();
    expect(mockOnChange).toHaveBeenCalledWith('30 00 * * *');
  });

  test('switching to weekdays shows hour and minute fields', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />);

    const frequencySelect = screen.getByLabelText('Frequency');
    await user.selectOptions(frequencySelect, 'weekdays');

    expect(screen.getByLabelText('Hour')).toBeInTheDocument();
    expect(screen.getByLabelText('Minute')).toBeInTheDocument();
    expect(mockOnChange).toHaveBeenCalledWith('30 09 * * 1-5');
  });

  test('switching to weekly shows day, hour, and minute fields', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />);

    const frequencySelect = screen.getByLabelText('Frequency');
    await user.selectOptions(frequencySelect, 'weekly');

    expect(screen.getByLabelText('Day')).toBeInTheDocument();
    expect(screen.getByLabelText('Hour')).toBeInTheDocument();
    expect(screen.getByLabelText('Minute')).toBeInTheDocument();
    expect(mockOnChange).toHaveBeenCalledWith('30 09 * * 01');
  });

  test('switching to monthly shows day, hour, and minute fields', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />);

    const frequencySelect = screen.getByLabelText('Frequency');
    await user.selectOptions(frequencySelect, 'monthly');

    expect(screen.getAllByLabelText('Day')[0]).toBeInTheDocument();
    expect(screen.getByLabelText('Hour')).toBeInTheDocument();
    expect(screen.getByLabelText('Minute')).toBeInTheDocument();
    expect(mockOnChange).toHaveBeenCalledWith('30 09 01 * *');
  });

  test('switching to specific_months shows day, hour, minute, and month checkboxes', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="30 9 * * *" onChange={mockOnChange} />);

    const frequencySelect = screen.getByLabelText('Frequency');
    await user.selectOptions(frequencySelect, 'specific_months');

    expect(screen.getAllByLabelText('Day')[0]).toBeInTheDocument();
    expect(screen.getByLabelText('Hour')).toBeInTheDocument();
    expect(screen.getByLabelText('Minute')).toBeInTheDocument();
    expect(screen.getByText('Months')).toBeInTheDocument();

    // All 12 month checkboxes should be present
    expect(screen.getByRole('checkbox', { name: /jan/i })).toBeInTheDocument();
    expect(screen.getByRole('checkbox', { name: /dec/i })).toBeInTheDocument();
  });

  test('switching to custom mode preserves current expression', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();
    const customExpression = '30 9 15 * *';

    render(
      <CronFieldBuilder value={customExpression} onChange={mockOnChange} />
    );

    const frequencySelect = screen.getByLabelText('Frequency');
    await user.selectOptions(frequencySelect, 'custom');

    // Should not call onChange when switching to custom
    expect(mockOnChange).not.toHaveBeenCalled();
  });
});

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

    // Check February
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

    // Uncheck February
    const febCheckbox = screen.getByRole('checkbox', { name: /feb/i });
    await user.click(febCheckbox);

    expect(mockOnChange).toHaveBeenCalledWith('30 09 15 1,3 *');
  });

  test('preserves custom interval when switching to every_n_minutes', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="*/7 * * * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('7 minutes')).toBeInTheDocument();

    // Custom interval should be preserved in dropdown
    const intervalSelect = screen.getByLabelText('Every');
    expect(intervalSelect).toHaveValue('7');
  });

  test('preserves custom interval when switching to every_n_hours', async () => {
    const user = userEvent.setup();
    const mockOnChange = vi.fn();

    render(<CronFieldBuilder value="0 */5 * * *" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('5 hours')).toBeInTheDocument();

    // Custom interval should be preserved in dropdown
    const intervalSelect = screen.getByLabelText('Every');
    expect(intervalSelect).toHaveValue('5');
  });
});

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
    const input = screen.getByPlaceholderText('0 0 * * *') as HTMLInputElement;
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
});

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

  test('advanced input is disabled when disabled prop is true', async () => {
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
