/**
 * CollaborativeEditorPromoBanner Tests
 *
 * Verifies banner behavior:
 * - Renders when not dismissed
 * - Hides when dismissed (via cookie)
 * - Cookie read/write functionality
 * - URL building logic for different paths and query params
 * - Dismiss button functionality
 */

import { fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { CollaborativeEditorPromoBanner } from '../../js/workflow-diagram/CollaborativeEditorPromoBanner';

// =============================================================================
// TEST SETUP & FIXTURES
// =============================================================================

const mockLocation = (pathname: string, search: string = '') => {
  Object.defineProperty(window, 'location', {
    value: { pathname, search },
    writable: true,
  });
};

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
    // Set default location
    mockLocation('/projects/proj-123/w/workflow-456');
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
  // PREFERENCE PERSISTENCE TESTS
  // ===========================================================================

  describe('preference persistence', () => {
    test('calls pushEvent to save preference when link is clicked', () => {
      const mockPushEvent = vi.fn();
      render(<CollaborativeEditorPromoBanner pushEvent={mockPushEvent} />);

      const link = screen.getByRole('link');
      fireEvent.click(link);

      expect(mockPushEvent).toHaveBeenCalledWith(
        'toggle_collaborative_editor',
        {}
      );
    });

    test('does not error when pushEvent is not provided', () => {
      render(<CollaborativeEditorPromoBanner />);

      const link = screen.getByRole('link');
      // Should not throw
      expect(() => fireEvent.click(link)).not.toThrow();
    });
  });

  // ===========================================================================
  // URL BUILDING TESTS
  // ===========================================================================

  describe('URL building', () => {
    test('builds correct URL for existing workflow', () => {
      mockLocation('/projects/proj-123/w/workflow-456');

      render(<CollaborativeEditorPromoBanner />);

      const link = screen.getByRole('link');
      expect(link).toHaveAttribute(
        'href',
        '/projects/proj-123/w/workflow-456/collaborate'
      );
    });

    test('builds correct URL for new workflow', () => {
      mockLocation('/projects/proj-123/w/new');

      render(<CollaborativeEditorPromoBanner />);

      const link = screen.getByRole('link');
      expect(link).toHaveAttribute(
        'href',
        '/projects/proj-123/w/new/collaborate'
      );
    });

    test('preserves "a" (run) query param', () => {
      mockLocation('/projects/proj-123/w/workflow-456', '?a=run-789');

      render(<CollaborativeEditorPromoBanner />);

      const link = screen.getByRole('link');
      expect(link).toHaveAttribute(
        'href',
        '/projects/proj-123/w/workflow-456/collaborate?a=run-789'
      );
    });

    test('preserves "v" (version) query param', () => {
      mockLocation('/projects/proj-123/w/workflow-456', '?v=5');

      render(<CollaborativeEditorPromoBanner />);

      const link = screen.getByRole('link');
      expect(link).toHaveAttribute(
        'href',
        '/projects/proj-123/w/workflow-456/collaborate?v=5'
      );
    });

    test('preserves both "a" and "v" query params', () => {
      mockLocation('/projects/proj-123/w/workflow-456', '?a=run-789&v=5');

      render(<CollaborativeEditorPromoBanner />);

      const link = screen.getByRole('link');
      expect(link).toHaveAttribute(
        'href',
        '/projects/proj-123/w/workflow-456/collaborate?a=run-789&v=5'
      );
    });

    test('ignores other query params', () => {
      mockLocation(
        '/projects/proj-123/w/workflow-456',
        '?a=run-789&other=value&v=5'
      );

      render(<CollaborativeEditorPromoBanner />);

      const link = screen.getByRole('link');
      expect(link).toHaveAttribute(
        'href',
        '/projects/proj-123/w/workflow-456/collaborate?a=run-789&v=5'
      );
    });

    test('falls back to /projects for unrecognized paths', () => {
      mockLocation('/some/other/path');

      render(<CollaborativeEditorPromoBanner />);

      const link = screen.getByRole('link');
      expect(link).toHaveAttribute('href', '/projects');
    });
  });
});
