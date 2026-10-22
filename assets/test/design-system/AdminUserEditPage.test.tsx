import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { AdminUserEditPage } from '../../js/design-system/pages/AdminUserEditPage';

const user = {
  id: 'u1',
  firstName: 'Amara',
  lastName: 'Okafor',
  email: 'amara@example.org',
  role: 'user',
  supportUser: false,
  disabled: false,
  scheduledDeletion: null,
};

describe('AdminUserEditPage', () => {
  test('saves with the event and the camelCase values the LiveView reads', async () => {
    const pushEvent = vi.fn().mockResolvedValue({});
    render(
      <AdminUserEditPage
        data-props={JSON.stringify({ user })}
        pushEvent={pushEvent}
        handleEvent={vi.fn()}
        navigate={vi.fn()}
        redirect={vi.fn()}
      />
    );

    fireEvent.change(screen.getByLabelText('First Name'), {
      target: { value: 'Ama' },
    });
    fireEvent.click(
      screen.getByLabelText('A disabled user will not be allowed to login.')
    );
    fireEvent.submit(document.getElementById('user-form')!);

    await waitFor(() =>
      expect(pushEvent).toHaveBeenCalledWith('save_user', {
        firstName: 'Ama',
        lastName: 'Okafor',
        email: 'amara@example.org',
        password: '',
        role: 'user',
        supportUser: false,
        scheduledDeletion: '',
        disabled: true,
      })
    );
  });
});
