import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { FirstSetupPage } from '../../js/design-system/pages/FirstSetupPage';

const fill = (id: string, value: string) =>
  fireEvent.change(document.getElementById(id)!, { target: { value } });

describe('FirstSetupPage', () => {
  test('saves the five fields with one event, and shows the reply on its field', async () => {
    const pushEvent = vi.fn().mockResolvedValue({
      error: 'Please fix the errors below.',
      fieldErrors: { email: ['has already been taken'] },
    });
    render(
      <FirstSetupPage
        data-props="{}"
        pushEvent={pushEvent}
        handleEvent={vi.fn()}
        navigate={vi.fn()}
        redirect={vi.fn()}
      />
    );
    fill('first_name', 'Test');
    fill('last_name', 'McTest');
    fill('email', 'foo@example.com');
    fill('password', '1234567890ab');
    fill('password_confirmation', '1234567890ab');
    fireEvent.submit(document.getElementById('superuser-registration-form')!);

    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('save', {
        firstName: 'Test',
        lastName: 'McTest',
        email: 'foo@example.com',
        password: '1234567890ab',
        passwordConfirmation: '1234567890ab',
      })
    );
    expect(
      await screen.findByText('has already been taken')
    ).toBeInTheDocument();
  });
});
