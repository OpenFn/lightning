/**
 * Breadcrumbs Component Tests
 *
 * Focuses on BreadcrumbText's dual rendering: a plain, non-interactive label by
 * default, and a clickable button when an onClick handler is provided (used to
 * make the workflow title navigate back to the root workflow editor view).
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test, vi } from 'vitest';

import { BreadcrumbText } from '../../../js/collaborative-editor/components/Breadcrumbs';

describe('BreadcrumbText', () => {
  test('renders as non-interactive text when no onClick is provided', () => {
    render(<BreadcrumbText>My Workflow</BreadcrumbText>);

    expect(screen.getByText('My Workflow')).toBeInTheDocument();
    expect(screen.queryByRole('button')).not.toBeInTheDocument();
  });

  test('renders as a button and fires onClick when clicked', async () => {
    const handleClick = vi.fn();
    render(
      <BreadcrumbText onClick={handleClick} title="Back to workflow editor">
        My Workflow
      </BreadcrumbText>
    );

    const button = screen.getByRole('button', { name: 'My Workflow' });
    expect(button).toHaveAttribute('title', 'Back to workflow editor');

    await userEvent.click(button);
    expect(handleClick).toHaveBeenCalledTimes(1);
  });
});
