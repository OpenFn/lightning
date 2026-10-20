import { renderHook } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { useLiveViewRouter } from '../../js/design-system/router';

describe('useLiveViewRouter', () => {
  const navigate = vi.fn();
  const redirect = vi.fn();
  const assign = vi.fn();
  const replace = vi.fn();

  beforeEach(() => {
    const url = new URL('http://localhost/profile/tokens');
    vi.stubGlobal('location', {
      href: url.href,
      origin: url.origin,
      pathname: url.pathname,
      search: url.search,
      hash: url.hash,
      assign,
      replace,
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
  });

  const go = (to: string, opts?: { replace?: boolean }) =>
    renderHook(() =>
      useLiveViewRouter({ navigate, redirect }, '/profile/tokens')
    ).result.current.navigate(to, opts);

  test('patches paths under its own path', () => {
    go('/profile/tokens/abc/delete');
    go('?x=1', { replace: true });

    expect(navigate).toHaveBeenNthCalledWith(
      1,
      '/profile/tokens/abc/delete',
      undefined
    );
    expect(navigate).toHaveBeenNthCalledWith(2, '/profile/tokens?x=1', {
      replace: true,
    });
    expect(redirect).not.toHaveBeenCalled();
  });

  test('live-redirects other in-app paths', () => {
    go('/profile/tokens-old');
    go('/projects', { replace: true });

    expect(redirect).toHaveBeenNthCalledWith(
      1,
      '/profile/tokens-old',
      undefined
    );
    expect(redirect).toHaveBeenNthCalledWith(2, '/projects', {
      replace: true,
    });
    expect(navigate).not.toHaveBeenCalled();
  });

  test('leaves hash jumps and other origins to the browser', () => {
    go('#top');
    go('https://other.example/', { replace: true });

    expect(assign).toHaveBeenCalledWith(
      new URL('http://localhost/profile/tokens#top')
    );
    expect(replace).toHaveBeenCalledWith(new URL('https://other.example/'));
    expect(navigate).not.toHaveBeenCalled();
    expect(redirect).not.toHaveBeenCalled();
  });
});
