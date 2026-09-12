/**
 * PromotedNotice
 *
 * Archiving a sandbox is the server's navigation, and the flash that arrives
 * with it speaks only of the archive. This says the other half, once, on the
 * far side of the reload.
 */
import { render } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { PromotedNotice } from '../../../js/collaborative-editor/components/PromotedNotice';
import {
  clearPromoted,
  markPromoted,
} from '../../../js/collaborative-editor/lib/promoteHandoff';

const success = vi.fn();

vi.mock('../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: {
    success: (...args: unknown[]) => success(...args),
  },
}));

describe('PromotedNotice', () => {
  beforeEach(() => {
    success.mockClear();
    clearPromoted();
  });

  afterEach(() => {
    clearPromoted();
  });

  test('says nothing when no promote preceded this page', () => {
    render(<PromotedNotice />);

    expect(success).not.toHaveBeenCalled();
  });

  test('confirms the promote once the marker is there', () => {
    markPromoted();

    render(<PromotedNotice />);

    expect(success).toHaveBeenCalledTimes(1);
    expect(success.mock.calls[0]?.[0]).toMatchObject({
      title: 'Promoted to parent project',
    });
  });

  test('does not replay on a refresh', () => {
    // The marker is consumed when read, so a second load of the same tab is
    // silent. Otherwise every refresh would re-announce a promote from before.
    markPromoted();

    render(<PromotedNotice />).unmount();
    render(<PromotedNotice />);

    expect(success).toHaveBeenCalledTimes(1);
  });
});
