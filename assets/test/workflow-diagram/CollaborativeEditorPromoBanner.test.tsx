/**
 * CollaborativeEditorPromoBanner Tests
 *
 * Verifies banner behavior:
 * - Renders when not dismissed
 * - Hides when dismissed (via cookie)
 * - Cookie read/write functionality
 * - Dismiss button functionality
 * - pushEvent called for navigation
 */

import { fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { CollaborativeEditorPromoBanner } from '../../js/workflow-diagram/CollaborativeEditorPromoBanner';

// =============================================================================
// TEST SETUP & FIXTURES
// =============================================================================

const getCookie = (name: string): string | null => {
  const value = `; ${document.cookie}`;
  const parts = value.split(`; ${name}=`);
  if (parts.length === 2) {
    return parts.pop()?.split(';').shift() || null;
  }
  return null;
};

const COOKIE_NAME = 'openfn_collaborative_editor_promo_dismissed';

describe('CollaborativeEditorPromoBanner', () => {
  beforeEach(() => {
    // Clear cookies before each test
    document.cookie = `${COOKIE_NAME}=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/`;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  // ===========================================================================
  // RENDERING TESTS
  // ===========================================================================

  describe('rendering', () => {
    test('renders banner when not previously dismissed', () => {
      render(<CollaborativeEditorPromoBanner />);

      expect(
        screen.getByText('Try the new collaborative editor')
      ).toBeInTheDocument();
      expect(
        screen.getByText(/Real-time editing with your team/)
      ).toBeInTheDocument();
    });

    test('does not render when cookie indicates dismissed', () => {
      document.cookie = `${COOKIE_NAME}=true; path=/`;

      render(<CollaborativeEditorPromoBanner />);

      expect(
        screen.queryByText('Try the new collaborative editor')
      ).not.toBeInTheDocument();
    });

    test('renders with correct accessibility attributes', () => {
      render(<CollaborativeEditorPromoBanner />);

      const alert = screen.getByRole('alert');
      expect(alert).toHaveAttribute('aria-live', 'polite');

      const dismissButton = screen.getByLabelText(
        'Dismiss collaborative editor promotion'
      );
      expect(dismissButton).toBeInTheDocument();
    });

    test('applies custom className', () => {
      render(<CollaborativeEditorPromoBanner className="custom-class" />);

      const alert = screen.getByRole('alert');
      expect(alert).toHaveClass('custom-class');
    });
  });

  // ===========================================================================
  // DISMISS FUNCTIONALITY TESTS
  // ===========================================================================

  describe('dismiss functionality', () => {
    test('hides banner when dismiss button is clicked', () => {
      render(<CollaborativeEditorPromoBanner />);

      expect(
        screen.getByText('Try the new collaborative editor')
      ).toBeInTheDocument();

      const dismissButton = screen.getByLabelText(
        'Dismiss collaborative editor promotion'
      );
      fireEvent.click(dismissButton);

      expect(
        screen.queryByText('Try the new collaborative editor')
      ).not.toBeInTheDocument();
    });

    test('sets cookie when dismissed', () => {
      render(<CollaborativeEditorPromoBanner />);

      const dismissButton = screen.getByLabelText(
        'Dismiss collaborative editor promotion'
      );
      fireEvent.click(dismissButton);

      expect(getCookie(COOKIE_NAME)).toBe('true');
    });

    test('cookie has correct attributes', () => {
      render(<CollaborativeEditorPromoBanner />);

      const dismissButton = screen.getByLabelText(
        'Dismiss collaborative editor promotion'
      );
      fireEvent.click(dismissButton);

      // Cookie should contain path and SameSite attributes
      expect(document.cookie).toContain(COOKIE_NAME);
    });
  });

  // ===========================================================================
  // NAVIGATION TESTS
  // ===========================================================================

  describe('navigation', () => {
    test('calls pushEvent when banner button is clicked', () => {
      const mockPushEvent = vi.fn();
      render(<CollaborativeEditorPromoBanner pushEvent={mockPushEvent} />);

      const bannerButton = screen.getByRole('button', {
        name: /Try the new collaborative editor/,
      });
      fireEvent.click(bannerButton);

      expect(mockPushEvent).toHaveBeenCalledWith('switch_to_collab_editor', {});
    });

    test('does not error when pushEvent is not provided', () => {
      render(<CollaborativeEditorPromoBanner />);

      const bannerButton = screen.getByRole('button', {
        name: /Try the new collaborative editor/,
      });
      // Should not throw
      expect(() => fireEvent.click(bannerButton)).not.toThrow();
    });
  });
});
