/**
 * Tests for SearchableList component library
 *
 * Tests the reusable SearchableList, ListSection, and ListRow components
 * that provide search and selection UI patterns.
 */

import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { SearchableList } from '../../../js/collaborative-editor/components/SearchableList/SearchableList';
import { ListSection } from '../../../js/collaborative-editor/components/SearchableList/ListSection';
import { ListRow } from '../../../js/collaborative-editor/components/SearchableList/ListRow';

describe('SearchableList', () => {
  it('renders search input with placeholder', () => {
    render(
      <SearchableList placeholder="Search items..." onSearch={() => {}}>
        <div>Content</div>
      </SearchableList>
    );

    expect(screen.getByPlaceholderText('Search items...')).toBeInTheDocument();
  });

  it('auto-focuses search input on mount', () => {
    render(
      <SearchableList onSearch={() => {}}>
        <div>Content</div>
      </SearchableList>
    );

    expect(screen.getByRole('combobox')).toHaveFocus();
  });

  it('does not auto-focus when autoFocus is false', () => {
    render(
      <SearchableList autoFocus={false} onSearch={() => {}}>
        <div>Content</div>
      </SearchableList>
    );

    expect(screen.getByRole('combobox')).not.toHaveFocus();
  });

  it('calls onSearch callback when typing', () => {
    const onSearch = vi.fn();
    render(
      <SearchableList onSearch={onSearch}>
        <div>Content</div>
      </SearchableList>
    );

    const input = screen.getByRole('combobox');
    fireEvent.change(input, { target: { value: 'test' } });

    expect(onSearch).toHaveBeenCalledWith('test');
  });

  it('shows clear button when input has value', () => {
    render(
      <SearchableList onSearch={() => {}}>
        <div>Content</div>
      </SearchableList>
    );

    const input = screen.getByRole('combobox');

    // No clear button initially
    expect(screen.queryByRole('button')).not.toBeInTheDocument();

    // Type something
    fireEvent.change(input, { target: { value: 'test' } });

    // Clear button appears
    expect(screen.getByRole('button')).toBeInTheDocument();
  });

  it('clears input and calls onSearch when clear button clicked', () => {
    const onSearch = vi.fn();
    render(
      <SearchableList onSearch={onSearch}>
        <div>Content</div>
      </SearchableList>
    );

    const input = screen.getByRole('combobox') as HTMLInputElement;

    // Type something
    fireEvent.change(input, { target: { value: 'test' } });
    expect(input.value).toBe('test');

    // Click clear button
    const clearButton = screen.getByRole('button');
    fireEvent.click(clearButton);

    // Input is cleared
    expect(input.value).toBe('');
    // onSearch called with empty string
    expect(onSearch).toHaveBeenCalledWith('');
  });

  it('renders children content', () => {
    render(
      <SearchableList onSearch={() => {}}>
        <div data-testid="child-content">Test Content</div>
      </SearchableList>
    );

    expect(screen.getByTestId('child-content')).toBeInTheDocument();
    expect(screen.getByText('Test Content')).toBeInTheDocument();
  });

  it('calls onKeyDown when arrow keys are pressed', () => {
    const onKeyDown = vi.fn();
    render(
      <SearchableList onSearch={() => {}} onKeyDown={onKeyDown}>
        <div>Content</div>
      </SearchableList>
    );

    const input = screen.getByRole('combobox');

    // Press ArrowDown
    fireEvent.keyDown(input, { key: 'ArrowDown', code: 'ArrowDown' });
    expect(onKeyDown).toHaveBeenCalledTimes(1);

    // Press ArrowUp
    fireEvent.keyDown(input, { key: 'ArrowUp', code: 'ArrowUp' });
    expect(onKeyDown).toHaveBeenCalledTimes(2);
  });

  it('calls onKeyDown after typing in input', () => {
    const onKeyDown = vi.fn();
    render(
      <SearchableList onSearch={() => {}} onKeyDown={onKeyDown}>
        <div>Content</div>
      </SearchableList>
    );

    const input = screen.getByRole('combobox');

    // Type some text
    fireEvent.change(input, { target: { value: 'test' } });

    // Arrow keys should still work after typing
    fireEvent.keyDown(input, { key: 'ArrowDown', code: 'ArrowDown' });
    expect(onKeyDown).toHaveBeenCalledTimes(1);

    fireEvent.keyDown(input, { key: 'ArrowUp', code: 'ArrowUp' });
    expect(onKeyDown).toHaveBeenCalledTimes(2);
  });
});

describe('ListSection', () => {
  it('renders title and children', () => {
    render(
      <ListSection title="Test Section">
        <div>Child content</div>
      </ListSection>
    );

    expect(screen.getByText('Test Section')).toBeInTheDocument();
    expect(screen.getByText('Child content')).toBeInTheDocument();
  });

  it('renders title as h3 heading', () => {
    render(
      <ListSection title="Test Section">
        <div>Content</div>
      </ListSection>
    );

    const heading = screen.getByText('Test Section');
    expect(heading.tagName).toBe('H3');
  });

  it('renders multiple children', () => {
    render(
      <ListSection title="Items">
        <div>Item 1</div>
        <div>Item 2</div>
        <div>Item 3</div>
      </ListSection>
    );

    expect(screen.getByText('Item 1')).toBeInTheDocument();
    expect(screen.getByText('Item 2')).toBeInTheDocument();
    expect(screen.getByText('Item 3')).toBeInTheDocument();
  });
});

describe('ListRow', () => {
  it('renders title', () => {
    render(<ListRow title="Item Title" />);
    expect(screen.getByText('Item Title')).toBeInTheDocument();
  });

  it('renders title and description', () => {
    render(<ListRow title="Item Title" description="Item Description" />);

    expect(screen.getByText('Item Title')).toBeInTheDocument();
    expect(screen.getByText('Item Description')).toBeInTheDocument();
  });

  it('renders without description when not provided', () => {
    render(<ListRow title="Item Title" />);

    expect(screen.getByText('Item Title')).toBeInTheDocument();
    // Description div should not be rendered
    expect(screen.queryByText(/Latest:|Version:/)).not.toBeInTheDocument();
  });

  it('renders icon when provided', () => {
    render(
      <ListRow title="Item" icon={<span data-testid="test-icon">Icon</span>} />
    );

    expect(screen.getByTestId('test-icon')).toBeInTheDocument();
  });

  it('does not render icon container when icon not provided', () => {
    const { container } = render(<ListRow title="Item" />);

    // Check that no shrink-0 div exists (the icon container)
    const iconContainers = container.querySelectorAll('.shrink-0');
    expect(iconContainers.length).toBe(0);
  });

  it('calls onClick when clicked', () => {
    const onClick = vi.fn();
    render(<ListRow title="Item" onClick={onClick} />);

    fireEvent.click(screen.getByRole('option'));
    expect(onClick).toHaveBeenCalledTimes(1);
  });

  it('shows checkmark icon when selected', () => {
    const { container, rerender } = render(
      <ListRow title="Item" selected={false} />
    );

    // No checkmark when not selected
    expect(container.querySelector('.hero-check')).not.toBeInTheDocument();

    // Rerender with selected=true
    rerender(<ListRow title="Item" selected={true} />);

    // Checkmark appears
    expect(container.querySelector('.hero-check')).toBeInTheDocument();
  });

  it('renders as a button with proper type and option role', () => {
    render(<ListRow title="Item" />);

    const button = screen.getByRole('option');
    expect(button.tagName).toBe('BUTTON');
    expect(button).toHaveAttribute('type', 'button');
    expect(button).toHaveAttribute('role', 'option');
  });

  it('combines icon, title, description, and checkmark correctly', () => {
    const { container } = render(
      <ListRow
        title="Salesforce"
        description="Latest: 2.1.0"
        icon={<img data-testid="icon" alt="salesforce" />}
        selected={true}
      />
    );

    // All elements present
    expect(screen.getByTestId('icon')).toBeInTheDocument();
    expect(screen.getByText('Salesforce')).toBeInTheDocument();
    expect(screen.getByText('Latest: 2.1.0')).toBeInTheDocument();
    expect(container.querySelector('.hero-check')).toBeInTheDocument();
  });
});
