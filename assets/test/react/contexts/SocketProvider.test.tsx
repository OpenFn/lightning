import { render } from '@testing-library/react';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';

import { SocketProvider } from '../../../js/react/contexts/SocketProvider';

const { disconnect } = vi.hoisted(() => ({ disconnect: vi.fn() }));

vi.mock('phoenix', () => ({
  Socket: vi.fn(() => ({
    connect: vi.fn(),
    disconnect,
    onOpen: vi.fn(),
    onError: vi.fn(),
    onClose: vi.fn(),
  })),
}));

beforeEach(() => {
  Object.assign(window, { userToken: 'token' });
});

afterEach(() => {
  Reflect.deleteProperty(window, 'userToken');
  disconnect.mockClear();
});

test('closes the socket when unmounted', () => {
  const { unmount } = render(<SocketProvider>{null}</SocketProvider>);
  expect(disconnect).not.toHaveBeenCalled();

  unmount();

  expect(disconnect).toHaveBeenCalledOnce();
});
