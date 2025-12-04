/**
 * TemplateSearchInput Component Tests
 *
 * Tests the TemplateSearchInput component including:
 * - Rendering with placeholder
 * - Controlled value handling
 * - Debounced onChange callback
 * - Clear button functionality
 * - Focus on mount behavior
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, act } from '@testing-library/react';
import { TemplateSearchInput } from '../../../../js/collaborative-editor/components/left-panel/TemplateSearchInput';

describe('TemplateSearchInput', () => {
  let mockOnChange: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockOnChange = vi.fn();
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('renders with default placeholder', () => {
    render(<TemplateSearchInput value="" onChange={mockOnChange} />);

    expect(
      screen.getByPlaceholderText('Search templates...')
    ).toBeInTheDocument();
  });

  it('renders with custom placeholder', () => {
    render(
      <TemplateSearchInput
        value=""
        onChange={mockOnChange}
        placeholder="Find a template..."
      />
    );

    expect(
      screen.getByPlaceholderText('Find a template...')
    ).toBeInTheDocument();
  });

  it('displays the provided value', () => {
    render(<TemplateSearchInput value="test query" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('test query')).toBeInTheDocument();
  });

  it('updates local value immediately on input', () => {
    render(<TemplateSearchInput value="" onChange={mockOnChange} />);

    const input = screen.getByPlaceholderText('Search templates...');
    fireEvent.change(input, { target: { value: 'new query' } });

    expect(screen.getByDisplayValue('new query')).toBeInTheDocument();
  });

  it('debounces onChange callback by 300ms', async () => {
    render(<TemplateSearchInput value="" onChange={mockOnChange} />);

    const input = screen.getByPlaceholderText('Search templates...');
    fireEvent.change(input, { target: { value: 'debounced' } });

    // Should not be called immediately
    expect(mockOnChange).not.toHaveBeenCalled();

    // Advance timers by 299ms - still not called
    act(() => {
      vi.advanceTimersByTime(299);
    });
    expect(mockOnChange).not.toHaveBeenCalled();

    // Advance to 300ms - now should be called
    act(() => {
      vi.advanceTimersByTime(1);
    });
    expect(mockOnChange).toHaveBeenCalledWith('debounced');
  });

  it('cancels pending debounce when new input arrives', async () => {
    render(<TemplateSearchInput value="" onChange={mockOnChange} />);

    const input = screen.getByPlaceholderText('Search templates...');

    // First input
    fireEvent.change(input, { target: { value: 'first' } });
    act(() => {
      vi.advanceTimersByTime(200);
    });

    // Second input before debounce completes
    fireEvent.change(input, { target: { value: 'second' } });
    act(() => {
      vi.advanceTimersByTime(300);
    });

    // Should only be called with 'second', not 'first'
    expect(mockOnChange).toHaveBeenCalledTimes(1);
    expect(mockOnChange).toHaveBeenCalledWith('second');
  });

  it('shows clear button when value is present', () => {
    render(<TemplateSearchInput value="test" onChange={mockOnChange} />);

    expect(screen.getByLabelText('Clear search')).toBeInTheDocument();
  });

  it('hides clear button when value is empty', () => {
    render(<TemplateSearchInput value="" onChange={mockOnChange} />);

    expect(screen.queryByLabelText('Clear search')).not.toBeInTheDocument();
  });

  it('clears input immediately when clear button is clicked', () => {
    render(<TemplateSearchInput value="test" onChange={mockOnChange} />);

    const clearButton = screen.getByLabelText('Clear search');
    fireEvent.click(clearButton);

    // Should call onChange immediately with empty string (no debounce)
    expect(mockOnChange).toHaveBeenCalledWith('');
    expect(screen.getByDisplayValue('')).toBeInTheDocument();
  });

  it('syncs local value when external value prop changes', () => {
    const { rerender } = render(
      <TemplateSearchInput value="initial" onChange={mockOnChange} />
    );

    expect(screen.getByDisplayValue('initial')).toBeInTheDocument();

    rerender(<TemplateSearchInput value="updated" onChange={mockOnChange} />);

    expect(screen.getByDisplayValue('updated')).toBeInTheDocument();
  });

  it('has search icon', () => {
    const { container } = render(
      <TemplateSearchInput value="" onChange={mockOnChange} />
    );

    expect(
      container.querySelector('.hero-magnifying-glass')
    ).toBeInTheDocument();
  });

  it('cleans up timeout on unmount', () => {
    const clearTimeoutSpy = vi.spyOn(global, 'clearTimeout');

    const { unmount } = render(
      <TemplateSearchInput value="" onChange={mockOnChange} />
    );

    const input = screen.getByPlaceholderText('Search templates...');
    fireEvent.change(input, { target: { value: 'test' } });

    unmount();

    // Verify cleanup happened
    expect(clearTimeoutSpy).toHaveBeenCalled();

    clearTimeoutSpy.mockRestore();
  });

  describe('onEnter callback', () => {
    it('calls onEnter when Enter key is pressed', () => {
      const mockOnEnter = vi.fn();
      render(
        <TemplateSearchInput
          value="test"
          onChange={mockOnChange}
          onEnter={mockOnEnter}
        />
      );

      const input = screen.getByPlaceholderText('Search templates...');
      fireEvent.keyDown(input, { key: 'Enter' });

      expect(mockOnEnter).toHaveBeenCalledTimes(1);
    });

    it('does not call onEnter for other keys', () => {
      const mockOnEnter = vi.fn();
      render(
        <TemplateSearchInput
          value="test"
          onChange={mockOnChange}
          onEnter={mockOnEnter}
        />
      );

      const input = screen.getByPlaceholderText('Search templates...');
      fireEvent.keyDown(input, { key: 'Escape' });
      fireEvent.keyDown(input, { key: 'Tab' });
      fireEvent.keyDown(input, { key: 'a' });

      expect(mockOnEnter).not.toHaveBeenCalled();
    });

    it('works without onEnter prop (no error thrown)', () => {
      render(<TemplateSearchInput value="test" onChange={mockOnChange} />);

      const input = screen.getByPlaceholderText('Search templates...');

      // Should not throw
      expect(() => {
        fireEvent.keyDown(input, { key: 'Enter' });
      }).not.toThrow();
    });
  });
});
