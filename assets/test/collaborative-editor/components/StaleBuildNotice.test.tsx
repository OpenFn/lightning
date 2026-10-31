import { render } from '@testing-library/react';
import { afterEach, expect, test, vi } from 'vitest';

import { StaleBuildNotice } from '../../../js/collaborative-editor/components/StaleBuildNotice';
import { notifications } from '../../../js/collaborative-editor/lib/notifications';

vi.mock('../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: { info: vi.fn(), dismiss: vi.fn() },
}));

afterEach(() => {
  vi.clearAllMocks();
});

test('shows one info toast once the server reports a changed build', () => {
  const { rerender } = render(<StaleBuildNotice staticChanged={false} />);
  expect(notifications.info).not.toHaveBeenCalled();

  rerender(<StaleBuildNotice staticChanged={true} />);

  expect(notifications.info).toHaveBeenCalledOnce();
  const [options] = vi.mocked(notifications.info).mock.calls[0];
  expect(options.id).toBe('stale-build');
  expect(options.duration).toBe(Infinity);
  expect(options.action).toMatchObject({ label: 'Reload' });
});

test('dismisses the toast when a later mount reports the build is current', () => {
  const { rerender } = render(<StaleBuildNotice staticChanged={true} />);

  rerender(<StaleBuildNotice staticChanged={false} />);

  expect(notifications.dismiss).toHaveBeenCalledWith('stale-build');
});
