import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { AuthConfirmationRequiredPage } from '../../js/design-system/pages/AuthConfirmationRequiredPage';

describe('AuthConfirmationRequiredPage', () => {
  test('asks with the events the LiveView answers, and shows the answers', async () => {
    const pushEvent = vi
      .fn()
      .mockResolvedValueOnce({ status: 'throttled', message: 'Try later.' })
      .mockResolvedValueOnce({
        error: 'Please fix the errors below.',
        fieldErrors: { currentPassword: ['Your passwords do not match.'] },
      })
      .mockResolvedValueOnce({ status: 'requested', email: 'new@example.org' });
    render(
      <AuthConfirmationRequiredPage
        data-props={JSON.stringify({ email: 'una@example.org' })}
        pushEvent={pushEvent}
        handleEvent={vi.fn()}
        navigate={vi.fn()}
        redirect={vi.fn()}
      />
    );

    fireEvent.click(
      screen.getByRole('button', { name: 'Resend confirmation email' })
    );
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('resend_confirmation_email', {})
    );
    expect(await screen.findByText('Try later.')).toBeTruthy();

    fireEvent.change(screen.getByLabelText(/New email address/), {
      target: { value: 'new@example.org' },
    });
    fireEvent.change(screen.getByLabelText(/Enter password to confirm/), {
      target: { value: 'hello world!' },
    });
    fireEvent.submit(document.getElementById('email-form')!);
    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('change_email', {
        email: 'new@example.org',
        currentPassword: 'hello world!',
      })
    );
    // The kit turns the reply's field errors into the form's.
    expect(
      await screen.findByText('Your passwords do not match.')
    ).toBeTruthy();
    fireEvent.change(screen.getByLabelText(/Enter password to confirm/), {
      target: { value: 'hello world!' },
    });
    fireEvent.submit(document.getElementById('email-form')!);
    expect(
      await screen.findByText(
        'We have sent confirmation instructions to new@example.org.'
      )
    ).toBeTruthy();
    expect(
      screen.getByRole('link', { name: 'Log out' }).getAttribute('href')
    ).toBe('/users/log_out');
  });
});
