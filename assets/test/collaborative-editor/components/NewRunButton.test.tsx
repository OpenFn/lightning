/**
 * NewRunButton Component Tests
 *
 * Tests for the NewRunButton component focusing on the disabled prop behavior.
 * Verifies that the button correctly respects both the disabled prop and useCanRun hook.
 */

import { render, screen } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { NewRunButton } from '../../../js/collaborative-editor/components/NewRunButton';

// Mock useCanRun hook
vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useCanRun: () => ({
    canRun: true,
    tooltipMessage: 'Run workflow',
  }),
}));

describe('NewRunButton - Disabled Prop', () => {
  test('button is disabled when disabled prop is true', () => {
    const mockOnClick = vi.fn();

    render(<NewRunButton onClick={mockOnClick} disabled={true} />);

    const button = screen.getByRole('button', { name: /run/i });
    expect(button).toBeDisabled();
  });

  test('button is enabled when disabled prop is false and canRun is true', () => {
    const mockOnClick = vi.fn();

    render(<NewRunButton onClick={mockOnClick} disabled={false} />);

    const button = screen.getByRole('button', { name: /run/i });
    expect(button).not.toBeDisabled();
  });

  test('button is enabled when disabled prop is undefined and canRun is true', () => {
    const mockOnClick = vi.fn();

    render(<NewRunButton onClick={mockOnClick} />);

    const button = screen.getByRole('button', { name: /run/i });
    expect(button).not.toBeDisabled();
  });

  test('button respects disabled prop even when canRun is true', () => {
    const mockOnClick = vi.fn();

    // useCanRun returns canRun: true (mocked above)
    // But disabled prop should take precedence
    render(<NewRunButton onClick={mockOnClick} disabled={true} />);

    const button = screen.getByRole('button', { name: /run/i });
    expect(button).toBeDisabled();
  });

  test('button renders with play icon', () => {
    const mockOnClick = vi.fn();

    const { container } = render(
      <NewRunButton onClick={mockOnClick} disabled={false} />
    );

    const playIcon = container.querySelector('.hero-play');
    expect(playIcon).toBeInTheDocument();
  });

  test('button renders with "Run" text', () => {
    const mockOnClick = vi.fn();

    render(<NewRunButton onClick={mockOnClick} disabled={false} />);

    expect(screen.getByText('Run')).toBeInTheDocument();
  });
});

describe('NewRunButton - Tooltip Positioning', () => {
  test('renders with default tooltip position (bottom)', () => {
    const mockOnClick = vi.fn();

    render(<NewRunButton onClick={mockOnClick} />);

    const button = screen.getByRole('button', { name: /run/i });
    expect(button).toBeInTheDocument();
    // Tooltip position is passed to Tooltip component, which is tested separately
  });

  test('renders with custom tooltip position (top)', () => {
    const mockOnClick = vi.fn();

    render(<NewRunButton onClick={mockOnClick} tooltipSide="top" />);

    const button = screen.getByRole('button', { name: /run/i });
    expect(button).toBeInTheDocument();
    // Tooltip position is passed to Tooltip component, which is tested separately
  });
});
