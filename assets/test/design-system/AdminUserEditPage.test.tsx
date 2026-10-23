import { fireEvent, screen, waitFor } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import {
  AdminUserEditPage,
  type Props,
} from '../../js/design-system/pages/AdminUserEditPage';

import { renderIsland } from './renderIsland';

const user: Props['user'] = {
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
    const { pushEvent } = renderIsland<Props>(AdminUserEditPage, { user });

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
