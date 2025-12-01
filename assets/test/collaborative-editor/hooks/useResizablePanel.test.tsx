/**
 * useResizablePanel Hook Tests
 *
 * Tests the useResizablePanel hook including:
 * - Width initialization from localStorage
 * - Default width fallback
 * - Resize behavior (left and right directions)
 * - Viewport-aware constraints
 * - localStorage persistence
 * - Mouse event handling
 */

import { renderHook, act, waitFor } from '@testing-library/react';
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { useResizablePanel } from '../../../js/collaborative-editor/hooks/useResizablePanel';

describe('useResizablePanel', () => {
  beforeEach(() => {
    // Clear localStorage before each test
    localStorage.clear();
    // Mock window.innerWidth
    Object.defineProperty(window, 'innerWidth', {
      writable: true,
      configurable: true,
      value: 1920,
    });
  });

  afterEach(() => {
    localStorage.clear();
  });

  describe('initialization', () => {
    it('uses default width when no saved value exists', () => {
      const { result } = renderHook(() =>
        useResizablePanel({
          storageKey: 'test-panel-width',
          defaultWidth: 400,
        })
      );

      expect(result.current.width).toBe(400);
    });

    it('uses saved width from localStorage when available', () => {
      localStorage.setItem('test-panel-width', '500');

      const { result } = renderHook(() =>
        useResizablePanel({
          storageKey: 'test-panel-width',
          defaultWidth: 400,
        })
      );

      expect(result.current.width).toBe(500);
    });

    it('starts with isResizing as false', () => {
      const { result } = renderHook(() =>
        useResizablePanel({
          storageKey: 'test-panel-width',
          defaultWidth: 400,
        })
      );

      expect(result.current.isResizing).toBe(false);
    });
  });

  describe('resizing behavior', () => {
    it('sets isResizing to true when handleMouseDown is called', () => {
      const { result } = renderHook(() =>
        useResizablePanel({
          storageKey: 'test-panel-width',
          defaultWidth: 400,
        })
      );

      const mockEvent = {
        preventDefault: vi.fn(),
        clientX: 500,
      } as any;

      act(() => {
        result.current.handleMouseDown(mockEvent);
      });

      expect(result.current.isResizing).toBe(true);
      expect(mockEvent.preventDefault).toHaveBeenCalled();
    });

    it('updates width when mouse moves (right direction)', async () => {
      const { result } = renderHook(() =>
        useResizablePanel({
          storageKey: 'test-panel-width',
          defaultWidth: 400,
          direction: 'right',
        })
      );

      // Start resizing
      const mouseDownEvent = {
        preventDefault: vi.fn(),
        clientX: 400,
      } as any;

      act(() => {
        result.current.handleMouseDown(mouseDownEvent);
      });

      // Simulate mouse move 100px to the right
      const mouseMoveEvent = new MouseEvent('mousemove', {
        clientX: 500,
      });

      act(() => {
        document.dispatchEvent(mouseMoveEvent);
      });

      await waitFor(() => {
        expect(result.current.width).toBe(500); // 400 + 100
      });
    });

    it('updates width when mouse moves (left direction)', async () => {
      const { result } = renderHook(() =>
        useResizablePanel({
          storageKey: 'test-panel-width',
          defaultWidth: 400,
          direction: 'left',
        })
      );

      // Start resizing
      const mouseDownEvent = {
        preventDefault: vi.fn(),
        clientX: 500,
      } as any;

      act(() => {
        result.current.handleMouseDown(mouseDownEvent);
      });

      // Simulate mouse move 100px to the left (decrease clientX)
      const mouseMoveEvent = new MouseEvent('mousemove', {
        clientX: 400,
      });

      act(() => {
        document.dispatchEvent(mouseMoveEvent);
      });

      await waitFor(() => {
        expect(result.current.width).toBe(500); // 400 + (500 - 400)
      });
    });

    it('sets isResizing to false on mouse up', async () => {
      const { result } = renderHook(() =>
        useResizablePanel({
          storageKey: 'test-panel-width',
          defaultWidth: 400,
        })
      );

      // Start resizing
      const mouseDownEvent = {
        preventDefault: vi.fn(),
        clientX: 400,
      } as any;

      act(() => {
        result.current.handleMouseDown(mouseDownEvent);
      });

      expect(result.current.isResizing).toBe(true);

      // Simulate mouse up
      const mouseUpEvent = new MouseEvent('mouseup');

      act(() => {
        document.dispatchEvent(mouseUpEvent);
      });

      await waitFor(() => {
        expect(result.current.isResizing).toBe(false);
      });
    });
  });

  describe('viewport constraints', () => {
    it('respects minimum pixel width', async () => {
      const { result } = renderHook(() =>
        useResizablePanel({
          storageKey: 'test-panel-width',
          defaultWidth: 400,
          minPixels: 300,
        })
      );

      // Try to resize below minimum
      const mouseDownEvent = {
        preventDefault: vi.fn(),
        clientX: 400,
      } as any;

      act(() => {
        result.current.handleMouseDown(mouseDownEvent);
      });

      // Move far to the left
      const mouseMoveEvent = new MouseEvent('mousemove', {
        clientX: 100, // Would result in 200px
      });

      act(() => {
        document.dispatchEvent(mouseMoveEvent);
      });

      await waitFor(() => {
        expect(result.current.width).toBeGreaterThanOrEqual(300);
      });
    });

    it('respects maximum pixel width', async () => {
      const { result } = renderHook(() =>
        useResizablePanel({
          storageKey: 'test-panel-width',
          defaultWidth: 400,
          maxPixels: 600,
        })
      );

      // Try to resize above maximum
      const mouseDownEvent = {
        preventDefault: vi.fn(),
        clientX: 400,
      } as any;

      act(() => {
        result.current.handleMouseDown(mouseDownEvent);
      });

      // Move far to the right
      const mouseMoveEvent = new MouseEvent('mousemove', {
        clientX: 1500, // Would result in 1500px
      });

      act(() => {
        document.dispatchEvent(mouseMoveEvent);
      });

      await waitFor(() => {
        expect(result.current.width).toBeLessThanOrEqual(600);
      });
    });

    it('respects viewport percentage minimum', async () => {
      window.innerWidth = 1000;

      const { result } = renderHook(() =>
        useResizablePanel({
          storageKey: 'test-panel-width',
          defaultWidth: 400,
          minPercent: 0.3, // 30% of 1000px = 300px
        })
      );

      const mouseDownEvent = {
        preventDefault: vi.fn(),
        clientX: 400,
      } as any;

      act(() => {
        result.current.handleMouseDown(mouseDownEvent);
      });

      // Try to resize to 200px
      const mouseMoveEvent = new MouseEvent('mousemove', {
        clientX: 200,
      });

      act(() => {
        document.dispatchEvent(mouseMoveEvent);
      });

      await waitFor(() => {
        expect(result.current.width).toBeGreaterThanOrEqual(300);
      });
    });

    it('respects viewport percentage maximum', async () => {
      window.innerWidth = 1000;

      const { result } = renderHook(() =>
        useResizablePanel({
          storageKey: 'test-panel-width',
          defaultWidth: 400,
          maxPercent: 0.5, // 50% of 1000px = 500px
        })
      );

      const mouseDownEvent = {
        preventDefault: vi.fn(),
        clientX: 400,
      } as any;

      act(() => {
        result.current.handleMouseDown(mouseDownEvent);
      });

      // Try to resize to 700px
      const mouseMoveEvent = new MouseEvent('mousemove', {
        clientX: 1100,
      });

      act(() => {
        document.dispatchEvent(mouseMoveEvent);
      });

      await waitFor(() => {
        expect(result.current.width).toBeLessThanOrEqual(500);
      });
    });
  });

  describe('localStorage persistence', () => {
    it('saves width to localStorage on mouse up', async () => {
      const { result } = renderHook(() =>
        useResizablePanel({
          storageKey: 'test-panel-width',
          defaultWidth: 400,
        })
      );

      // Start resizing
      const mouseDownEvent = {
        preventDefault: vi.fn(),
        clientX: 400,
      } as any;

      act(() => {
        result.current.handleMouseDown(mouseDownEvent);
      });

      // Move mouse
      const mouseMoveEvent = new MouseEvent('mousemove', {
        clientX: 500,
      });

      act(() => {
        document.dispatchEvent(mouseMoveEvent);
      });

      // End resizing
      const mouseUpEvent = new MouseEvent('mouseup');

      act(() => {
        document.dispatchEvent(mouseUpEvent);
      });

      await waitFor(() => {
        const saved = localStorage.getItem('test-panel-width');
        expect(saved).toBeTruthy();
        expect(parseInt(saved!, 10)).toBeGreaterThan(400);
      });
    });

    it('uses different storage keys for different panels', () => {
      const { result: result1 } = renderHook(() =>
        useResizablePanel({
          storageKey: 'left-panel-width',
          defaultWidth: 300,
        })
      );

      const { result: result2 } = renderHook(() =>
        useResizablePanel({
          storageKey: 'right-panel-width',
          defaultWidth: 500,
        })
      );

      expect(result1.current.width).toBe(300);
      expect(result2.current.width).toBe(500);
    });
  });

  describe('cleanup', () => {
    it('removes event listeners on unmount', () => {
      const removeEventListenerSpy = vi.spyOn(document, 'removeEventListener');

      const { result, unmount } = renderHook(() =>
        useResizablePanel({
          storageKey: 'test-panel-width',
          defaultWidth: 400,
        })
      );

      // Start resizing to trigger listener setup
      const mouseDownEvent = {
        preventDefault: vi.fn(),
        clientX: 400,
      } as any;

      act(() => {
        result.current.handleMouseDown(mouseDownEvent);
      });

      unmount();

      expect(removeEventListenerSpy).toHaveBeenCalledWith(
        'mousemove',
        expect.any(Function)
      );
      expect(removeEventListenerSpy).toHaveBeenCalledWith(
        'mouseup',
        expect.any(Function)
      );

      removeEventListenerSpy.mockRestore();
    });
  });
});
