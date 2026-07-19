// Tests for BreadcrumbText: the truncating workflow-name label gains a tooltip
// so long names stay readable on hover, while non-string children render as-is.

import { render, screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import { BreadcrumbText } from '../../../js/collaborative-editor/components/Breadcrumbs';

describe('BreadcrumbText', () => {
  const LONG_NAME =
    'A very long workflow name that will be truncated by max-w-[16rem]';

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
