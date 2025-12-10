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
  test('displays version information and action button', () => {
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
      screen.getByText(/You're viewing a run from v15 on workflow v19/)
    ).toBeInTheDocument();

    // Check action button is present
    const actionButton = screen.getByRole('button', { name: /Go to v15/ });
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
    const actionButton = screen.getByRole('button', { name: /Go to v15/ });
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

  test('applies max-width constraint when compact', () => {
    const onGoToVersion = vi.fn();
    const { container } = render(
      <VersionMismatchBanner
        runVersion={15}
        currentVersion={19}
        onGoToVersion={onGoToVersion}
        compact={true}
      />
    );

    // Check that the text container has the max-w class
    const textContainer = container.querySelector('.max-w-\\[150px\\]');
    expect(textContainer).toBeInTheDocument();
  });

  test('does not apply max-width constraint when not compact', () => {
    const onGoToVersion = vi.fn();
    const { container } = render(
      <VersionMismatchBanner
        runVersion={15}
        currentVersion={19}
        onGoToVersion={onGoToVersion}
        compact={false}
      />
    );

    // Check that the text container does not have the max-w class
    const textContainer = container.querySelector('.max-w-\\[150px\\]');
    expect(textContainer).not.toBeInTheDocument();
  });
});
