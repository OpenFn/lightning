/**
 * VersionMismatchBanner Component Tests
 *
 * Tests the version mismatch banner that appears when
 * the canvas version differs from the selected run's version.
 */

import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { VersionMismatchBanner } from '../../../../js/collaborative-editor/components/diagram/VersionMismatchBanner';

describe('VersionMismatchBanner', () => {
  test('displays version information and action button when not compact', () => {
    const onGoToVersion = vi.fn();
    render(
      <VersionMismatchBanner
        runVersion={15}
        currentVersion={19}
        onGoToVersion={onGoToVersion}
      />
    );

    // Check version info is displayed
    expect(
      screen.getByText(/This run took place on version 15/)
    ).toBeInTheDocument();

    // Check action button is present
    const actionButton = screen.getByRole('button', {
      name: /View as executed/,
    });
    expect(actionButton).toBeInTheDocument();
  });

  test('calls onGoToVersion when action button is clicked', () => {
    const onGoToVersion = vi.fn();
    render(
      <VersionMismatchBanner
        runVersion={15}
        currentVersion={19}
        onGoToVersion={onGoToVersion}
      />
    );

    // Click action button
    const actionButton = screen.getByRole('button', {
      name: /View as executed/,
    });
    fireEvent.click(actionButton);

    // Handler should be called
    expect(onGoToVersion).toHaveBeenCalledTimes(1);
  });

  test('shows information icon', () => {
    const onGoToVersion = vi.fn();
    render(
      <VersionMismatchBanner
        runVersion={15}
        currentVersion={19}
        onGoToVersion={onGoToVersion}
      />
    );

    // Check for info icon (hero-information-circle)
    const icon = document.querySelector('.hero-information-circle');
    expect(icon).toBeInTheDocument();
  });

  test('applies custom className', () => {
    const onGoToVersion = vi.fn();
    const { container } = render(
      <VersionMismatchBanner
        runVersion={15}
        currentVersion={19}
        onGoToVersion={onGoToVersion}
        className="custom-class"
      />
    );

    const banner = container.firstChild as HTMLElement;
    expect(banner).toHaveClass('custom-class');
  });

  test('hides version text when compact', () => {
    const onGoToVersion = vi.fn();
    render(
      <VersionMismatchBanner
        runVersion={15}
        currentVersion={19}
        onGoToVersion={onGoToVersion}
        compact={true}
      />
    );

    // Version text should not be present in compact mode
    expect(
      screen.queryByText(/This run took place on version 15/)
    ).not.toBeInTheDocument();

    // But button should still be present
    const actionButton = screen.getByRole('button', {
      name: /View as executed/,
    });
    expect(actionButton).toBeInTheDocument();
  });

  test('shows version text when not compact', () => {
    const onGoToVersion = vi.fn();
    render(
      <VersionMismatchBanner
        runVersion={15}
        currentVersion={19}
        onGoToVersion={onGoToVersion}
        compact={false}
      />
    );

    // Version text should be visible
    expect(
      screen.getByText(/This run took place on version 15/)
    ).toBeInTheDocument();
  });
});
