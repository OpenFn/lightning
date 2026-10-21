import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test, vi } from 'vitest';

import { AdminAuditPage } from '../../js/design-system/pages/AdminAuditPage';

const event = {
  id: 'audit-1',
  event: 'snapshot_created',
  itemType: 'workflow',
  itemId: '11111111-2222-3333-4444-555555555555',
  actorId: '66666666-7777-8888-9999-000000000000',
  actorLabel: 'Amy Admin',
  actorIdentifier: 'amy@example.com',
  insertedAt: '2026-10-14T18:36:12Z',
  changes: { before: null, after: null },
  credentialBodies: null,
};

describe('AdminAuditPage', () => {
  test('a page link patches the LiveView', async () => {
    window.history.replaceState(null, '', '/settings/audit');
    const navigate = vi.fn();
    render(
      <AdminAuditPage
        data-props={JSON.stringify({
          events: [event],
          pageNumber: 1,
          pageSize: 10,
          totalEntries: 25,
        })}
        pushEvent={vi.fn()}
        handleEvent={vi.fn()}
        navigate={navigate}
        redirect={vi.fn()}
      />
    );

    expect(screen.getByText('Amy Admin')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('link', { name: '3' }));

    expect(navigate).toHaveBeenCalledWith('/settings/audit?page=3', undefined);
  });
});
