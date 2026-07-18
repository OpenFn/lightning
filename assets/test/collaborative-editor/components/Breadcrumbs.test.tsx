/**
 * Breadcrumbs Component Tests
 *
 * Covers the two breadcrumb primitives:
 * - BreadcrumbLink: an anchor for real navigation (href) or a button for
 *   actions (onClick only). The workflow title uses the button mode to return
 *   to the root workflow editor view.
 * - BreadcrumbText: a plain, non-interactive label.
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test, vi } from 'vitest';

import {
  BreadcrumbLink,
  BreadcrumbText,
} from '../../../js/collaborative-editor/components/Breadcrumbs';

describe('BreadcrumbLink', () => {
  test('renders a button (not a link) and fires onClick when no href is given', async () => {
    const handleClick = vi.fn();
    render(<BreadcrumbLink onClick={handleClick}>My Workflow</BreadcrumbLink>);

    const button = screen.getByRole('button', { name: 'My Workflow' });
    expect(screen.queryByRole('link')).not.toBeInTheDocument();

    await userEvent.click(button);
    expect(handleClick).toHaveBeenCalledTimes(1);
  });

  test('renders an anchor with the given href for navigation', () => {
    render(
      <BreadcrumbLink href="/projects/123/w">Workflows</BreadcrumbLink>
    );

    const link = screen.getByRole('link', { name: 'Workflows' });
    expect(link).toHaveAttribute('href', '/projects/123/w');
  });
});

describe('BreadcrumbText', () => {
  test('renders plain, non-interactive text', () => {
    render(<BreadcrumbText>My Workflow</BreadcrumbText>);

    expect(screen.getByText('My Workflow')).toBeInTheDocument();
    expect(screen.queryByRole('button')).not.toBeInTheDocument();
    expect(screen.queryByRole('link')).not.toBeInTheDocument();
  });
});
