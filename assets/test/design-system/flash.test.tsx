import { render, screen, waitFor } from '@testing-library/react';
import { expect, test, vi } from 'vitest';

import { FlashBridge, Toaster } from '../../js/design-system/flash';

// What LayoutComponents.flash_bridge renders, and the hook's LiveView side
const bridge = (data: Record<string, string>) => {
  const el = document.createElement('div');
  Object.assign(el.dataset, data);
  const pushEvent = vi.fn();
  const hook = Object.assign(Object.create(FlashBridge), { el, pushEvent });
  return { hook, pushEvent };
};

test('a flash shows as a toast and is cleared once shown', async () => {
  // Published before the toaster renders, as on a slow first load
  const { hook, pushEvent } = bridge({ info: 'Saved', error: 'Not allowed' });
  hook.mounted();

  render(<Toaster />);

  expect(await screen.findByRole('status')).toHaveTextContent('Saved');
  expect(screen.getByRole('alert')).toHaveTextContent('Not allowed');
  expect(pushEvent).toHaveBeenCalledWith('lv:clear-flash', { key: 'info' });
  expect(pushEvent).toHaveBeenCalledWith('lv:clear-flash', { key: 'error' });

  // Another patch arrives before the clear does; nothing shows twice
  hook.updated();
  expect(screen.getAllByText(/Saved|Not allowed/)).toHaveLength(2);
  expect(pushEvent).toHaveBeenCalledTimes(2);

  // The cleared flash re-renders the element empty; nothing new shows
  delete hook.el.dataset['info'];
  delete hook.el.dataset['error'];
  hook.updated();
  expect(screen.getAllByText(/Saved|Not allowed/)).toHaveLength(2);
  expect(pushEvent).toHaveBeenCalledTimes(2);

  // The same message flashed again toasts again
  hook.el.dataset['info'] = 'Saved';
  hook.updated();
  await waitFor(() => expect(screen.getAllByText('Saved')).toHaveLength(2));
  expect(pushEvent).toHaveBeenCalledTimes(3);
});
