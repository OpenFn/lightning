/**
 * VersionMismatchBanner Component Tests
 *
 * Tests the dismissible version mismatch banner that appears when
 * the canvas version differs from the selected run's version.
 */

import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import { VersionMismatchBanner } from '../../../../js/collaborative-editor/components/diagram/VersionMismatchBanner';

describe('VersionMismatchBanner', () => {
  test('displays version information and dismiss button', () => {
    render(<VersionMismatchBanner runVersion={159} currentVersion={155} />);

    // Check version info is displayed
    expect(
      screen.getByText(/Canvas shows v155 \(Selected run: v159\)/)
    ).toBeInTheDocument();
    expect(
      screen.getByText(/Canvas layout may differ from actual run/)
    ).toBeInTheDocument();

    // Check dismiss button is present
    const dismissButton = screen.getByLabelText(
      'Dismiss version mismatch warning'
    );
    expect(dismissButton).toBeInTheDocument();
  });

  test('dismisses banner when X button is clicked', () => {
    const { container } = render(
      <VersionMismatchBanner runVersion={159} currentVersion={155} />
    );

    // Banner should be visible initially
    expect(
      screen.getByText(/Canvas shows v155 \(Selected run: v159\)/)
    ).toBeInTheDocument();

    // Click dismiss button
    const dismissButton = screen.getByLabelText(
      'Dismiss version mismatch warning'
    );
    fireEvent.click(dismissButton);

    // Banner should be removed from DOM
    expect(container.firstChild).toBeNull();
  });

  test('shows information icon instead of warning icon', () => {
    render(<VersionMismatchBanner runVersion={159} currentVersion={155} />);

    // Check for info icon (hero-information-circle)
    const icon = document.querySelector('.hero-information-circle');
    expect(icon).toBeInTheDocument();
  });

  test('applies custom className', () => {
    const { container } = render(
      <VersionMismatchBanner
        runVersion={159}
        currentVersion={155}
        className="custom-class"
      />
    );

    const banner = container.firstChild as HTMLElement;
    expect(banner).toHaveClass('custom-class');
  });
});
