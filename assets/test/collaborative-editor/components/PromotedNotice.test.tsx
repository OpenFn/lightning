// Tests for the on-load promote toast: reads the ?promoted marker left by a
// successful promote navigation, surfaces the success toast, then strips the
// marker so a refresh doesn't replay it.

import { render } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { PromotedNotice } from '../../../js/collaborative-editor/components/PromotedNotice';

const notifySuccess = vi.fn<(opts: { title: string; description?: string }) => void>();
vi.mock('../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: {
    success: (opts: { title: string; description?: string }) => {
      notifySuccess(opts);
    },
  },
}));

const setUrl = (url: string) => {
  window.history.replaceState({}, '', url);
};

describe('PromotedNotice', () => {
  beforeEach(() => {
    notifySuccess.mockReset();
  });

  afterEach(() => {
    setUrl('/');
  });

  test('shows the archived success toast and strips the marker from the URL', () => {
    setUrl('/projects/p1/w/wf1?promoted=1');

    render(<PromotedNotice />);

    expect(notifySuccess).toHaveBeenCalledTimes(1);
    const opts = notifySuccess.mock.calls[0]?.[0];
    expect(opts?.title).toBe('Promoted to parent project');
    expect(opts?.description).toContain('has been archived');

    // The one-shot markers are gone so a refresh won't replay the toast; the
    // rest of the path is preserved.
    expect(window.location.pathname).toBe('/projects/p1/w/wf1');
    expect(window.location.search).toBe('');
  });

  test('shows the softer message when the sandbox could not be archived', () => {
    setUrl('/projects/p1/w/wf1?promoted=1&archived=0');

    render(<PromotedNotice />);

    const opts = notifySuccess.mock.calls[0]?.[0];
    expect(opts?.description).toContain("couldn't be archived");
    expect(window.location.search).toBe('');
  });

  test('preserves unrelated query params while dropping the promote markers', () => {
    setUrl('/projects/p1/w/wf1?promoted=1&job=abc');

    render(<PromotedNotice />);

    expect(notifySuccess).toHaveBeenCalledTimes(1);
    expect(window.location.search).toBe('?job=abc');
  });

  test('does nothing when the promoted marker is absent', () => {
    setUrl('/projects/p1/w/wf1');

    render(<PromotedNotice />);

    expect(notifySuccess).not.toHaveBeenCalled();
  });
});
