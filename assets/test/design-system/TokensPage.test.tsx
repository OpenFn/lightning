import { act, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, test, vi } from 'vitest';

import { TokensPage } from '../../js/design-system/TokensPage';

const token = {
  id: 'abc',
  masked: '...0123456789',
  insertedAt: '2026-01-01T00:00:00Z',
  lastUsedAt: null,
};

const renderPage = ({
  tokenId,
  reply,
}: {
  tokenId?: string;
  reply?: Record<string, unknown>;
}) => {
  const pushEvent = vi.fn().mockResolvedValue(reply ?? {});
  const navigate = vi.fn();
  render(
    <TokensPage
      data-tokens={JSON.stringify([token])}
      data-token-id={tokenId}
      pushEvent={pushEvent}
      navigate={navigate}
      redirect={vi.fn()}
    />
  );
  return { pushEvent, navigate };
};

describe('TokensPage', () => {
  afterEach(() => {
    window.history.replaceState(null, '', '/');
  });

  test("a refused delete surfaces the reply error and doesn't navigate", async () => {
    window.history.replaceState(null, '', '/profile/tokens/abc/delete');
    const { pushEvent, navigate } = renderPage({
      tokenId: 'abc',
      reply: { error: "You can't perform this action" },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Yes' }));

    expect(
      await screen.findByText("You can't perform this action")
    ).toBeInTheDocument();
    expect(pushEvent).toHaveBeenCalledWith('delete_token', { id: 'abc' });
    expect(navigate).not.toHaveBeenCalled();
  });

  test("a delete doesn't patch again once the LiveView has", async () => {
    // The LiveView patches back to the list before it replies.
    window.history.replaceState(null, '', '/profile/tokens');
    const { pushEvent, navigate } = renderPage({ tokenId: 'abc' });

    await userEvent.click(screen.getByRole('button', { name: 'Yes' }));
    await waitFor(() => expect(pushEvent).toHaveBeenCalled());
    await act(async () => {});

    expect(navigate).not.toHaveBeenCalled();
  });

  test('Cancel goes back to the list', async () => {
    window.history.replaceState(null, '', '/profile/tokens/abc/delete');
    const { navigate } = renderPage({ tokenId: 'abc' });

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(navigate).toHaveBeenCalledWith('/profile/tokens');
  });

  test('no token id, no modal', () => {
    renderPage({});

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });
});
