import { screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import {
  MfaRequiredPage,
  type Props,
} from '../../js/design-system/pages/MfaRequiredPage';

import { renderIsland } from './renderIsland';

describe('MfaRequiredPage', () => {
  test('explains the block and links to the profile', () => {
    renderIsland<Props>(MfaRequiredPage, {});

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
