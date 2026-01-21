/* eslint-disable @typescript-eslint/unbound-method */
// Disabled because we reference navigator.clipboard.writeText in expect() calls
// which TypeScript sees as an unbound method. This is safe in tests where we're
// checking if the mocked method was called, not actually calling it.
import { renderHook, act } from '@testing-library/react';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import { useCopyToClipboard } from '#/collaborative-editor/hooks/useCopyToClipboard';

describe('useCopyToClipboard', () => {
  beforeEach(() => {
    // Mock clipboard API
    Object.assign(navigator, {
      clipboard: {
        writeText: vi.fn(() => Promise.resolve()),
      },
    });
  });

  it('should start in idle state', () => {
    const { result } = renderHook(() => useCopyToClipboard());
    expect(result.current.copyStatus).toBe('idle');
    expect(result.current.copyText).toBe('');
    expect(result.current.isCopied).toBe(false);
    expect(result.current.isError).toBe(false);
  });

  it('should copy text and show success state', async () => {
    const { result } = renderHook(() => useCopyToClipboard());

    await act(async () => {
      await result.current.copyToClipboard('test text');
    });

    expect(navigator.clipboard.writeText).toHaveBeenCalledWith('test text');
    expect(result.current.copyStatus).toBe('copied');
    expect(result.current.copyText).toBe('Copied!');
    expect(result.current.isCopied).toBe(true);
    expect(result.current.isError).toBe(false);
  });

  it('should reset to idle after 2 second timeout', async () => {
    vi.useFakeTimers();
    const { result } = renderHook(() => useCopyToClipboard());

    await act(async () => {
      await result.current.copyToClipboard('test');
    });

    expect(result.current.copyStatus).toBe('copied');

    act(() => {
      vi.advanceTimersByTime(2000);
    });

    expect(result.current.copyStatus).toBe('idle');
    expect(result.current.copyText).toBe('');
    vi.useRealTimers();
  });

  it('should handle clipboard errors and show error state', async () => {
    Object.assign(navigator, {
      clipboard: {
        writeText: vi.fn(() => Promise.reject(new Error('Permission denied'))),
      },
    });

    const { result } = renderHook(() => useCopyToClipboard());

    await act(async () => {
      await result.current.copyToClipboard('test');
    });

    expect(result.current.copyStatus).toBe('error');
    expect(result.current.copyText).toBe('Failed');
    expect(result.current.isCopied).toBe(false);
    expect(result.current.isError).toBe(true);
  });

  it('should cleanup timeout on unmount', () => {
    const { result, unmount } = renderHook(() => useCopyToClipboard());

    act(() => {
      void result.current.copyToClipboard('test');
    });

    unmount();
    // Should not throw or cause memory leaks
  });

  it('should clear previous timeout when copying multiple times quickly', async () => {
    vi.useFakeTimers();
    const { result } = renderHook(() => useCopyToClipboard());

    // First copy
    await act(async () => {
      await result.current.copyToClipboard('first');
    });
    expect(result.current.copyStatus).toBe('copied');

    // Second copy before timeout (after 1 second)
    act(() => {
      vi.advanceTimersByTime(1000);
    });

    await act(async () => {
      await result.current.copyToClipboard('second');
    });

    expect(result.current.copyStatus).toBe('copied');

    // Should reset after 2 seconds from SECOND copy, not first
    act(() => {
      vi.advanceTimersByTime(2000);
    });

    expect(result.current.copyStatus).toBe('idle');
    vi.useRealTimers();
  });

  it('should log errors to console when clipboard operation fails', async () => {
    const consoleError = vi
      .spyOn(console, 'error')
      .mockImplementation(() => {});
    const error = new Error('Clipboard error');
    Object.assign(navigator, {
      clipboard: {
        writeText: vi.fn(() => Promise.reject(error)),
      },
    });

    const { result } = renderHook(() => useCopyToClipboard());

    await act(async () => {
      await result.current.copyToClipboard('test');
    });

    expect(consoleError).toHaveBeenCalledWith(
      'Failed to copy to clipboard:',
      error
    );

    consoleError.mockRestore();
  });
});
/* eslint-enable @typescript-eslint/unbound-method */
