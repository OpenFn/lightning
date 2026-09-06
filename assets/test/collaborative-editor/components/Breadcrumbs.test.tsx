/**
 * Breadcrumbs Component Tests
 *
 * Covers the two breadcrumb primitives:
 * - BreadcrumbLink: an anchor for real navigation (href) or a button for
 *   actions (onClick only). The workflow title uses the button mode to return
 *   to the root workflow editor view.
 * - BreadcrumbText: the truncating workflow-name label. A string child gains a
 *   tooltip so long names stay readable on hover; non-string children render
 *   as-is.
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
    render(<BreadcrumbLink href="/projects/123/w">Workflows</BreadcrumbLink>);

    const link = screen.getByRole('link', { name: 'Workflows' });
    expect(link).toHaveAttribute('href', '/projects/123/w');
  });
});

describe('BreadcrumbText', () => {
  const LONG_NAME =
    'A very long workflow name that will be truncated by max-w-[16rem]';

  test('renders non-interactive text', () => {
    render(<BreadcrumbText>My Workflow</BreadcrumbText>);

    expect(screen.getByText('My Workflow')).toBeInTheDocument();
    expect(screen.queryByRole('button')).not.toBeInTheDocument();
    expect(screen.queryByRole('link')).not.toBeInTheDocument();
  });

  test('wraps a string name in a tooltip trigger so the full name is reachable', () => {
    render(<BreadcrumbText>{LONG_NAME}</BreadcrumbText>);

    // The truncating span carries the full text and, being a Radix tooltip
    // trigger, exposes data-state. The tooltip content (revealed on hover)
    // mirrors that full name.
    const nameSpan = screen.getByText(LONG_NAME);
    expect(nameSpan).toHaveClass('truncate');
    expect(nameSpan).toHaveAttribute('data-state');
  });

  test('does not use a native title attribute', () => {
    render(<BreadcrumbText>{LONG_NAME}</BreadcrumbText>);

    expect(screen.getByText(LONG_NAME)).not.toHaveAttribute('title');
  });

  test('renders non-string children without a tooltip', () => {
    render(
      <BreadcrumbText>
        <span data-testid="custom-child">Custom</span>
      </BreadcrumbText>
    );

    const child = screen.getByTestId('custom-child');
    expect(child).toBeInTheDocument();
    // No tooltip trigger wraps a non-string child, so nothing exposes
    // data-state.
    expect(document.querySelector('[data-state]')).toBeNull();
  });
});
