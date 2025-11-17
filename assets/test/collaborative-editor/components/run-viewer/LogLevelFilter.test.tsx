/**
 * LogLevelFilter Component Tests
 *
 * Tests for LogLevelFilter dropdown component that allows users
 * to select log levels (debug, info, warn, error).
 *
 * Test Coverage:
 * - Rendering states (button, dropdown, icons)
 * - Dropdown interaction (open/close, click outside)
 * - Level selection and change callback
 * - Visual states (selected vs non-selected levels)
 * - Accessibility (ARIA attributes)
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import { LogLevelFilter } from '../../../../js/collaborative-editor/components/run-viewer/LogLevelFilter';

describe('LogLevelFilter', () => {
  const mockOnLevelChange = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('rendering', () => {
    test('displays the selected level', () => {
      render(
        <LogLevelFilter
          selectedLevel="info"
          onLevelChange={mockOnLevelChange}
        />
      );

      expect(screen.getByText('info')).toBeInTheDocument();
    });

    test('shows adjustments icon', () => {
      const { container } = render(
        <LogLevelFilter
          selectedLevel="debug"
          onLevelChange={mockOnLevelChange}
        />
      );

      const adjustmentsIcon = container.querySelector(
        '.hero-adjustments-vertical'
      );
      expect(adjustmentsIcon).toBeInTheDocument();
    });

    test('dropdown is initially closed', () => {
      render(
        <LogLevelFilter
          selectedLevel="warn"
          onLevelChange={mockOnLevelChange}
        />
      );

      // Dropdown menu should not be visible
      expect(screen.queryByRole('listbox')).not.toBeInTheDocument();
    });

    test('has proper ARIA attributes when closed', () => {
      render(
        <LogLevelFilter
          selectedLevel="error"
          onLevelChange={mockOnLevelChange}
        />
      );

      const button = screen.getByRole('button');
      expect(button).toHaveAttribute('aria-haspopup', 'listbox');
      expect(button).toHaveAttribute('aria-expanded', 'false');
    });
  });

  describe('dropdown interaction', () => {
    test('opens dropdown when button clicked', async () => {
      const user = userEvent.setup();

      render(
        <LogLevelFilter
          selectedLevel="info"
          onLevelChange={mockOnLevelChange}
        />
      );

      const button = screen.getByRole('button');
      await user.click(button);

      expect(screen.getByRole('listbox')).toBeInTheDocument();
      expect(button).toHaveAttribute('aria-expanded', 'true');
    });

    test('closes dropdown when button clicked again', async () => {
      const user = userEvent.setup();

      render(
        <LogLevelFilter
          selectedLevel="info"
          onLevelChange={mockOnLevelChange}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);
      expect(screen.getByRole('listbox')).toBeInTheDocument();

      // Close dropdown
      await user.click(button);
      await waitFor(() => {
        expect(screen.queryByRole('listbox')).not.toBeInTheDocument();
      });
    });

    test('closes dropdown when clicking outside', async () => {
      const user = userEvent.setup();

      const { container } = render(
        <div>
          <div data-testid="outside">Outside element</div>
          <LogLevelFilter
            selectedLevel="info"
            onLevelChange={mockOnLevelChange}
          />
        </div>
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);
      expect(screen.getByRole('listbox')).toBeInTheDocument();

      // Click outside
      const outside = screen.getByTestId('outside');
      await user.click(outside);

      await waitFor(() => {
        expect(screen.queryByRole('listbox')).not.toBeInTheDocument();
      });
    });

    test('closes dropdown after selecting a level', async () => {
      const user = userEvent.setup();

      render(
        <LogLevelFilter
          selectedLevel="info"
          onLevelChange={mockOnLevelChange}
        />
      );

      const button = screen.getByRole('button');

      // Open dropdown
      await user.click(button);
      expect(screen.getByRole('listbox')).toBeInTheDocument();

      // Click on debug option
      const debugOption = screen.getAllByText('debug')[0];
      await user.click(debugOption);

      await waitFor(() => {
        expect(screen.queryByRole('listbox')).not.toBeInTheDocument();
      });
    });
  });

  describe('level selection', () => {
    test('calls onLevelChange with debug when debug selected', async () => {
      const user = userEvent.setup();

      render(
        <LogLevelFilter
          selectedLevel="info"
          onLevelChange={mockOnLevelChange}
        />
      );

      // Open dropdown
      await user.click(screen.getByRole('button'));

      // Click debug option
      const debugOption = screen.getAllByText('debug')[0];
      await user.click(debugOption);

      expect(mockOnLevelChange).toHaveBeenCalledWith('debug');
      expect(mockOnLevelChange).toHaveBeenCalledTimes(1);
    });

    test('calls onLevelChange with info when info selected', async () => {
      const user = userEvent.setup();

      render(
        <LogLevelFilter
          selectedLevel="debug"
          onLevelChange={mockOnLevelChange}
        />
      );

      await user.click(screen.getByRole('button'));

      const infoOption = screen.getAllByText('info')[0];
      await user.click(infoOption);

      expect(mockOnLevelChange).toHaveBeenCalledWith('info');
    });

    test('calls onLevelChange with warn when warn selected', async () => {
      const user = userEvent.setup();

      render(
        <LogLevelFilter
          selectedLevel="info"
          onLevelChange={mockOnLevelChange}
        />
      );

      await user.click(screen.getByRole('button'));

      const warnOption = screen.getAllByText('warn')[0];
      await user.click(warnOption);

      expect(mockOnLevelChange).toHaveBeenCalledWith('warn');
    });

    test('calls onLevelChange with error when error selected', async () => {
      const user = userEvent.setup();

      render(
        <LogLevelFilter
          selectedLevel="info"
          onLevelChange={mockOnLevelChange}
        />
      );

      await user.click(screen.getByRole('button'));

      const errorOption = screen.getAllByText('error')[0];
      await user.click(errorOption);

      expect(mockOnLevelChange).toHaveBeenCalledWith('error');
    });

    test('all four levels are present in dropdown', async () => {
      const user = userEvent.setup();

      render(
        <LogLevelFilter
          selectedLevel="info"
          onLevelChange={mockOnLevelChange}
        />
      );

      await user.click(screen.getByRole('button'));

      const listbox = screen.getByRole('listbox');
      const options = listbox.querySelectorAll('[role="option"]');

      expect(options).toHaveLength(4);
      expect(screen.getAllByText('debug')[0]).toBeInTheDocument();
      expect(screen.getAllByText('info')[0]).toBeInTheDocument();
      expect(screen.getAllByText('warn')[0]).toBeInTheDocument();
      expect(screen.getAllByText('error')[0]).toBeInTheDocument();
    });
  });

  describe('visual states', () => {
    test('selected level shows font-semibold', async () => {
      const user = userEvent.setup();

      render(
        <LogLevelFilter
          selectedLevel="info"
          onLevelChange={mockOnLevelChange}
        />
      );

      await user.click(screen.getByRole('button'));

      const infoOption = screen
        .getAllByText('info')
        .find(el => el.classList.contains('truncate'));
      expect(infoOption).toHaveClass('font-semibold');
    });

    test('non-selected levels show font-normal', async () => {
      const user = userEvent.setup();

      render(
        <LogLevelFilter
          selectedLevel="info"
          onLevelChange={mockOnLevelChange}
        />
      );

      await user.click(screen.getByRole('button'));

      const debugOption = screen
        .getAllByText('debug')
        .find(el => el.classList.contains('truncate'));
      expect(debugOption).toHaveClass('font-normal');
      expect(debugOption).not.toHaveClass('font-semibold');
    });

    test('selected level shows checkmark icon', async () => {
      const user = userEvent.setup();

      const { container } = render(
        <LogLevelFilter
          selectedLevel="warn"
          onLevelChange={mockOnLevelChange}
        />
      );

      await user.click(screen.getByRole('button'));

      // Check that there's exactly one checkmark icon
      const checkmarks = container.querySelectorAll('.hero-check');
      expect(checkmarks).toHaveLength(1);
    });

    test('non-selected levels do not show checkmark', async () => {
      const user = userEvent.setup();

      render(
        <LogLevelFilter
          selectedLevel="error"
          onLevelChange={mockOnLevelChange}
        />
      );

      await user.click(screen.getByRole('button'));

      // All options should be visible
      const listbox = screen.getByRole('listbox');
      const options = listbox.querySelectorAll('[role="option"]');
      expect(options).toHaveLength(4);

      // Only the selected level (error) should have a checkmark
      const errorOption = options[3]; // error is the last option
      expect(errorOption.textContent).toContain('error');
      expect(errorOption.querySelector('.hero-check')).toBeInTheDocument();

      // Other options should not have checkmarks
      const debugOption = options[0];
      expect(debugOption.querySelector('.hero-check')).not.toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    test('button has correct role and attributes', () => {
      render(
        <LogLevelFilter
          selectedLevel="info"
          onLevelChange={mockOnLevelChange}
        />
      );

      const button = screen.getByRole('button');
      expect(button).toHaveAttribute('type', 'button');
      expect(button).toHaveAttribute('aria-haspopup', 'listbox');
      expect(button).toHaveAttribute('aria-expanded');
    });

    test('dropdown has listbox role when open', async () => {
      const user = userEvent.setup();

      render(
        <LogLevelFilter
          selectedLevel="info"
          onLevelChange={mockOnLevelChange}
        />
      );

      await user.click(screen.getByRole('button'));

      const listbox = screen.getByRole('listbox');
      expect(listbox).toBeInTheDocument();
    });

    test('dropdown options have option role', async () => {
      const user = userEvent.setup();

      render(
        <LogLevelFilter
          selectedLevel="info"
          onLevelChange={mockOnLevelChange}
        />
      );

      await user.click(screen.getByRole('button'));

      const options = screen.getAllByRole('option');
      expect(options).toHaveLength(4);
    });

    test('icons have aria-hidden attribute', () => {
      const { container } = render(
        <LogLevelFilter
          selectedLevel="info"
          onLevelChange={mockOnLevelChange}
        />
      );

      const adjustmentsIcon = container.querySelector(
        '.hero-adjustments-vertical'
      );
      const chevronIcon = container.querySelector('.hero-chevron-down');

      expect(adjustmentsIcon).toHaveAttribute('aria-hidden', 'true');
      expect(chevronIcon).toHaveAttribute('aria-hidden', 'true');
    });
  });
});
