/**
 * TemplateDetailsCard Component Tests
 *
 * Tests the TemplateDetailsCard component including:
 * - Rendering template details
 * - Null template handling
 * - Description fallback
 */

import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { TemplateDetailsCard } from '../../../js/collaborative-editor/components/TemplateDetailsCard';
import type { Template } from '../../../js/collaborative-editor/types/template';

describe('TemplateDetailsCard', () => {
  const mockTemplate: Template = {
    id: 'template-1',
    name: 'Event-based Workflow',
    description: 'Trigger a workflow with a webhook or API call',
    code: 'workflow yaml code',
    tags: ['webhook', 'api'],
    isBase: true,
  };

  it('renders template name and description', () => {
    render(<TemplateDetailsCard template={mockTemplate} />);

    expect(screen.getByText('Event-based Workflow')).toBeInTheDocument();
    expect(
      screen.getByText('Trigger a workflow with a webhook or API call')
    ).toBeInTheDocument();
  });

  it('renders fallback text when description is null', () => {
    const templateWithoutDesc: Template = {
      ...mockTemplate,
      description: null,
    };

    render(<TemplateDetailsCard template={templateWithoutDesc} />);

    expect(screen.getByText('Event-based Workflow')).toBeInTheDocument();
    expect(screen.getByText('No description provided')).toBeInTheDocument();
  });

  it('renders fallback text when description is empty string', () => {
    const templateWithEmptyDesc: Template = {
      ...mockTemplate,
      description: '',
    };

    render(<TemplateDetailsCard template={templateWithEmptyDesc} />);

    expect(screen.getByText('Event-based Workflow')).toBeInTheDocument();
    expect(screen.getByText('No description provided')).toBeInTheDocument();
  });

  it('renders nothing when template is null', () => {
    const { container } = render(<TemplateDetailsCard template={null} />);

    expect(container.firstChild).toBeNull();
  });

  it('has correct positioning classes', () => {
    const { container } = render(
      <TemplateDetailsCard template={mockTemplate} />
    );

    const card = container.firstChild as HTMLElement;
    expect(card).toHaveClass('absolute', 'top-4', 'left-4', 'right-4');
  });

  it('has correct z-index for layering', () => {
    const { container } = render(
      <TemplateDetailsCard template={mockTemplate} />
    );

    const card = container.firstChild as HTMLElement;
    expect(card).toHaveClass('z-[5]');
  });

  it('has semi-transparent background', () => {
    const { container } = render(
      <TemplateDetailsCard template={mockTemplate} />
    );

    const card = container.firstChild as HTMLElement;
    expect(card).toHaveClass('bg-white/50');
  });

  it('renders with long template name', () => {
    const longNameTemplate: Template = {
      ...mockTemplate,
      name: 'This is an extremely long workflow template name that should still render properly',
    };

    render(<TemplateDetailsCard template={longNameTemplate} />);

    expect(
      screen.getByText(
        'This is an extremely long workflow template name that should still render properly'
      )
    ).toBeInTheDocument();
  });

  it('renders with long description', () => {
    const longDescTemplate: Template = {
      ...mockTemplate,
      description:
        'This is a very long description that explains in great detail what this template does and how it should be used in various scenarios across different use cases',
    };

    render(<TemplateDetailsCard template={longDescTemplate} />);

    expect(
      screen.getByText(
        'This is a very long description that explains in great detail what this template does and how it should be used in various scenarios across different use cases'
      )
    ).toBeInTheDocument();
  });
});
