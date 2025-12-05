/**
 * DisclaimerScreen - Tests for AI Assistant disclaimer onboarding screen
 *
 * Tests the full-screen disclaimer shown before first use of AI Assistant.
 * Ensures proper rendering, button functionality, and user acknowledgment flow.
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import { DisclaimerScreen } from '../../../js/collaborative-editor/components/DisclaimerScreen';

describe('DisclaimerScreen', () => {
  let mockOnAccept: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockOnAccept = vi.fn();
    vi.clearAllMocks();
  });

  describe('Rendering', () => {
    it('should render the disclaimer screen', () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} />);

      expect(screen.getByText('Assistant')).toBeInTheDocument();
    });

    it('should render main disclaimer text', () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} />);

      expect(
        screen.getByText(/helps you design and build your workflows/)
      ).toBeInTheDocument();
      expect(
        screen.getByText(/responsible for reviewing and testing/)
      ).toBeInTheDocument();
    });

    it('should render the accept button', () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} />);

      expect(
        screen.getByRole('button', {
          name: /Get started/i,
        })
      ).toBeInTheDocument();
    });

    it('should render important warnings', () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} />);

      expect(
        screen.getByText(/Do not include real user data/)
      ).toBeInTheDocument();
      expect(
        screen.getByText(/Conversations may be stored/)
      ).toBeInTheDocument();
    });

    it('should render the OpenFn logo', () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} />);

      const logo = document.querySelector('img[alt="OpenFn"]');
      expect(logo).toBeInTheDocument();
      expect(logo?.getAttribute('src')).toBe('/images/logo.svg');
      expect(logo).toHaveClass('h-12');
      expect(logo).toHaveClass('w-12');
    });
  });

  describe('Button Interaction', () => {
    it('should call onAccept when button is clicked', async () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} />);

      const button = screen.getByRole('button', {
        name: /Get started/i,
      });
      await userEvent.click(button);

      expect(mockOnAccept).toHaveBeenCalledTimes(1);
    });

    it('should not call onAccept when button is disabled', async () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} disabled={true} />);

      const button = screen.getByRole('button', {
        name: /Get started/i,
      });

      expect(button).toBeDisabled();
      await userEvent.click(button);

      expect(mockOnAccept).not.toHaveBeenCalled();
    });

    it('should enable button by default', () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} />);

      const button = screen.getByRole('button', {
        name: /Get started/i,
      });

      expect(button).toBeEnabled();
    });

    it('should disable button when disabled prop is true', () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} disabled={true} />);

      const button = screen.getByRole('button', {
        name: /Get started/i,
      });

      expect(button).toBeDisabled();
    });
  });

  describe('Styling', () => {
    it('should apply centered layout', () => {
      const { container } = render(
        <DisclaimerScreen onAccept={mockOnAccept} />
      );

      const layout = container.querySelector('.justify-center');
      expect(layout).toBeInTheDocument();
    });

    it('should render Assistant heading', () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} />);

      expect(screen.getByText('Assistant')).toBeInTheDocument();
    });

    it('should apply disabled styles when button is disabled', () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} disabled={true} />);

      const button = screen.getByRole('button', {
        name: /Get started/i,
      });

      expect(button).toHaveClass('disabled:bg-gray-300');
      expect(button).toHaveClass('disabled:cursor-not-allowed');
    });

    it('should apply primary button styles when enabled', () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} />);

      const button = screen.getByRole('button', {
        name: /Get started/i,
      });

      expect(button).toHaveClass('bg-indigo-600');
      expect(button).toHaveClass('hover:bg-indigo-700');
      expect(button).toHaveClass('shadow-sm');
      expect(button).toHaveClass('hover:shadow-md');
    });
  });

  describe('Content Structure', () => {
    it('should have proper heading hierarchy', () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} />);

      const heading = screen.getByRole('heading', { name: /Assistant/i });
      expect(heading).toBeInTheDocument();
      expect(heading.tagName).toBe('H2');
    });

    it('should organize content in sections', () => {
      const { container } = render(
        <DisclaimerScreen onAccept={mockOnAccept} />
      );

      const sections = container.querySelectorAll('.space-y-4, .space-y-2');
      expect(sections.length).toBeGreaterThan(0);
    });

    it('should emphasize security warning with bold text', () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} />);

      // Check that the security warning is rendered with emphasis
      const warningText = screen.getByText(/Do not include real user data/);
      expect(warningText).toBeInTheDocument();
      expect(warningText).toHaveClass('font-medium');
      expect(warningText).toHaveClass('text-gray-900');
    });

    it('should have visual separator for disclaimers', () => {
      const { container } = render(
        <DisclaimerScreen onAccept={mockOnAccept} />
      );

      const disclaimerSection = container.querySelector(
        '.border-t.border-gray-200'
      );
      expect(disclaimerSection).toBeInTheDocument();
    });

    it('should use larger container width', () => {
      const { container } = render(
        <DisclaimerScreen onAccept={mockOnAccept} />
      );

      const contentContainer = container.querySelector('.max-w-lg');
      expect(contentContainer).toBeInTheDocument();
    });
  });

  describe('Props Handling', () => {
    it('should handle missing onAccept gracefully', () => {
      expect(() =>
        render(<DisclaimerScreen onAccept={(() => {}) as () => void} />)
      ).not.toThrow();
    });

    it('should handle disabled=false explicitly', () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} disabled={false} />);

      const button = screen.getByRole('button', {
        name: /Get started/i,
      });

      expect(button).toBeEnabled();
    });

    it('should handle disabled=undefined (default)', () => {
      render(<DisclaimerScreen onAccept={mockOnAccept} disabled={undefined} />);

      const button = screen.getByRole('button', {
        name: /Get started/i,
      });

      expect(button).toBeEnabled();
    });
  });
});
