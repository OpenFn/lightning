import { render, screen } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { MfaRequiredPage } from '../../js/design-system/pages/MfaRequiredPage';

describe('MfaRequiredPage', () => {
  test('explains the block and links to the profile', () => {
    render(
      <MfaRequiredPage
        data-props="{}"
        pushEvent={vi.fn()}
        handleEvent={vi.fn()}
        navigate={vi.fn()}
        redirect={vi.fn()}
      />
    );

    expect(
      screen.getByRole('heading', { name: 'MFA Required for Project' })
    ).toBeInTheDocument();
    expect(
      screen.getByText(
        /requires all members to use multi-factor authentication/
      )
    ).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'your account' })).toHaveAttribute(
      'href',
      '/profile'
    );
    expect(
      screen.getByRole('link', { name: 'Visit your account' })
    ).toHaveAttribute('href', '/profile');
  });
});
