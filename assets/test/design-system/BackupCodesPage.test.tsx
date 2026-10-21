import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, test, vi } from 'vitest';

import { BackupCodesPage } from '../../js/design-system/pages/BackupCodesPage';

const renderPage = (reply: Record<string, unknown> = {}) => {
  const pushEvent = vi.fn().mockResolvedValue(reply);
  render(
    <BackupCodesPage
      data-props={JSON.stringify({
        codes: [{ code: 'aaaa1111', usedAt: null }],
        mfaEnabled: true,
      })}
      pushEvent={pushEvent}
      handleEvent={vi.fn()}
      navigate={vi.fn()}
      redirect={vi.fn()}
    />
  );
  return { pushEvent };
};

describe('BackupCodesPage', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  test('regenerate pushes the event and shows a refused reply', async () => {
    const { pushEvent } = renderPage({
      error: 'Could not generate new backup codes',
    });

    await userEvent.click(
      screen.getByRole('button', { name: 'Generate new backup codes' })
    );

    expect(pushEvent).toHaveBeenCalledWith('regenerate-backup-codes', {});
    expect(
      await screen.findByText('Could not generate new backup codes')
    ).toBeInTheDocument();
  });

  test('print opens the printable copy in a new tab', async () => {
    const open = vi.fn();
    vi.stubGlobal('open', open);
    renderPage();

    await userEvent.click(screen.getByRole('button', { name: 'Print Codes' }));

    expect(open).toHaveBeenCalledWith(
      '/profile/auth/backup_codes/print',
      '_blank'
    );
  });
});
