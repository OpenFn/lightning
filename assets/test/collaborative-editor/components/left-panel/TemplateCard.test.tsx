/**
 * TemplateCard Component Tests
 *
 * Tests the TemplateCard component including:
 * - Rendering template information
 * - Selection state display
 * - Click and keyboard interaction
 * - Accessibility attributes
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { TemplateCard } from '../../../../js/collaborative-editor/components/left-panel/TemplateCard';
import type { Template } from '../../../../js/collaborative-editor/types/template';

describe('TemplateCard', () => {
  const mockBaseTemplate: Template = {
    id: 'test-template-1',
    name: 'Test Template',
    description: 'This is a test template description',
    code: 'workflow code here',
    tags: ['test', 'example'],
    isBase: true,
  };

  const mockUserTemplate: Template = {
    id: 'user-template-1',
    name: 'User Template',
    description: 'This is a user template description',
    code: 'workflow code here',
    tags: ['user', 'custom'],
    positions: null,
    workflow_id: null,
  };

  let mockOnClick: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockOnClick = vi.fn();
  });

  it('renders template name', () => {
    render(
      <TemplateCard
        template={mockBaseTemplate}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    expect(screen.getByText('Test Template')).toBeInTheDocument();
  });

  it('renders template description for user templates', () => {
    render(
      <TemplateCard
        template={mockUserTemplate}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    expect(
      screen.getByText('This is a user template description')
    ).toBeInTheDocument();
  });

  it('hides description for base templates', () => {
    render(
      <TemplateCard
        template={mockBaseTemplate}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    expect(
      screen.queryByText('This is a test template description')
    ).not.toBeInTheDocument();
  });

  it('shows base badge for base templates', () => {
    render(
      <TemplateCard
        template={mockBaseTemplate}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    expect(screen.getByText('base')).toBeInTheDocument();
  });

  it('does not show base badge for user templates', () => {
    render(
      <TemplateCard
        template={mockUserTemplate}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    expect(screen.queryByText('base')).not.toBeInTheDocument();
  });

  it('renders "No description provided" when description is missing', () => {
    const templateWithoutDesc: Template = {
      ...mockUserTemplate,
      description: null,
    };

    render(
      <TemplateCard
        template={templateWithoutDesc}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    expect(screen.getByText('No description provided')).toBeInTheDocument();
  });

  it('shows selected state visually', () => {
    const { container } = render(
      <TemplateCard
        template={mockBaseTemplate}
        isSelected={true}
        onClick={mockOnClick}
      />
    );

    const card = container.querySelector('[role="button"]');
    expect(card).toHaveClass('border-primary-500', 'bg-primary-50');
  });

  it('shows unselected state visually', () => {
    const { container } = render(
      <TemplateCard
        template={mockBaseTemplate}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    const card = container.querySelector('[role="button"]');
    expect(card).toHaveClass('border-gray-200', 'bg-white');
  });

  it('calls onClick when card is clicked', () => {
    render(
      <TemplateCard
        template={mockBaseTemplate}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    const card = screen.getByRole('button', { name: /test template/i });
    fireEvent.click(card);

    expect(mockOnClick).toHaveBeenCalledWith(mockBaseTemplate);
  });

  it('calls onClick when Enter key is pressed', () => {
    render(
      <TemplateCard
        template={mockBaseTemplate}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    const card = screen.getByRole('button', { name: /test template/i });
    fireEvent.keyDown(card, { key: 'Enter' });

    expect(mockOnClick).toHaveBeenCalledWith(mockBaseTemplate);
  });

  it('calls onClick when Space key is pressed', () => {
    render(
      <TemplateCard
        template={mockBaseTemplate}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    const card = screen.getByRole('button', { name: /test template/i });
    fireEvent.keyDown(card, { key: ' ' });

    expect(mockOnClick).toHaveBeenCalledWith(mockBaseTemplate);
  });

  it('does not call onClick for other keys', () => {
    render(
      <TemplateCard
        template={mockBaseTemplate}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    const card = screen.getByRole('button', { name: /test template/i });
    fireEvent.keyDown(card, { key: 'a' });

    expect(mockOnClick).not.toHaveBeenCalled();
  });

  it('has correct accessibility attributes when selected', () => {
    render(
      <TemplateCard
        template={mockBaseTemplate}
        isSelected={true}
        onClick={mockOnClick}
      />
    );

    const card = screen.getByRole('button', { name: /test template/i });
    expect(card).toHaveAttribute('aria-pressed', 'true');
    expect(card).toHaveAttribute('tabIndex', '0');
  });

  it('has correct accessibility attributes when not selected', () => {
    render(
      <TemplateCard
        template={mockBaseTemplate}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    const card = screen.getByRole('button', { name: /test template/i });
    expect(card).toHaveAttribute('aria-pressed', 'false');
    expect(card).toHaveAttribute('tabIndex', '0');
  });

  it('is keyboard focusable', () => {
    render(
      <TemplateCard
        template={mockBaseTemplate}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    const card = screen.getByRole('button', { name: /test template/i });
    card.focus();

    expect(card).toHaveFocus();
  });

  it('renders with long template name without breaking', () => {
    const longNameTemplate: Template = {
      ...mockBaseTemplate,
      name: 'This is a very long template name that should be truncated properly',
    };

    render(
      <TemplateCard
        template={longNameTemplate}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    expect(
      screen.getByText(
        'This is a very long template name that should be truncated properly'
      )
    ).toBeInTheDocument();
  });

  it('renders with long description without breaking', () => {
    const longDescTemplate: Template = {
      ...mockUserTemplate,
      description:
        'This is a very long description that goes on and on and should be clamped to two lines using the line-clamp-2 utility class',
    };

    render(
      <TemplateCard
        template={longDescTemplate}
        isSelected={false}
        onClick={mockOnClick}
      />
    );

    expect(
      screen.getByText(
        'This is a very long description that goes on and on and should be clamped to two lines using the line-clamp-2 utility class'
      )
    ).toBeInTheDocument();
  });
});
