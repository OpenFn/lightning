/**
 * PromotedNotice
 *
 * The server marks the editor it lands you on with `?archived=1` instead of
 * setting a flash, so the message arrives in the editor's own language. Whoever
 * promoted carries a second, local marker so their message names the promote.
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
  notifications: { success: (...args: unknown[]) => success(...args) },
}));

const land = (search: string) => {
  window.history.replaceState({}, '', `/projects/p/w/wf${search}`);
};

describe('PromotedNotice', () => {
  beforeEach(() => {
    success.mockClear();
    clearPromoted();
    land('');
  });

  afterEach(() => {
    clearPromoted();
  });

  test('says nothing on an ordinary visit', () => {
    render(<PromotedNotice />);

    expect(success).not.toHaveBeenCalled();
  });

  test('tells a bystander their sandbox was archived', () => {
    // They never promoted, so they hold no local marker. The server's marker is
    // the whole reason they know why the page moved.
    land('?archived=1');

    render(<PromotedNotice />);

    expect(success).toHaveBeenCalledTimes(1);
    expect(success.mock.calls[0]?.[0]).toMatchObject({
      title: 'Sandbox archived',
    });
  });

  test('names the promote for whoever did it', () => {
    land('?archived=1');
    markPromoted();

    render(<PromotedNotice />);

    expect(success.mock.calls[0]?.[0]).toMatchObject({
      title: 'Promoted to parent project',
    });
  });

  test('strips the marker so a refresh stays quiet', () => {
    land('?archived=1&panel=editor');

    render(<PromotedNotice />).unmount();

    expect(window.location.search).toBe('?panel=editor');

    render(<PromotedNotice />);
    expect(success).toHaveBeenCalledTimes(1);
  });

  test('drops a stale promote marker on an ordinary visit', () => {
    // Otherwise an archive that never happened would announce itself the next
    // time this tab opened an editor.
    markPromoted();

    render(<PromotedNotice />);

    expect(success).not.toHaveBeenCalled();

    land('?archived=1');
    render(<PromotedNotice />);
    expect(success.mock.calls[0]?.[0]).toMatchObject({
      title: 'Sandbox archived',
    });
  });
});
