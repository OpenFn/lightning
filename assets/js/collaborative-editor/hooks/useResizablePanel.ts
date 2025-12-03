/**
 * useResizablePanel - Shared hook for panel resizing with viewport-aware constraints
 *
 * Provides consistent resize behavior across panels with:
 * - Viewport-aware min/max constraints
 * - localStorage persistence
 * - Mouse event handling
 */

import { useEffect, useRef, useState } from 'react';

interface UseResizablePanelOptions {
  /** localStorage key for persisting panel width */
  storageKey: string;
  /** Default width in pixels */
  defaultWidth: number;
  /** Minimum width as percentage of viewport (0-1) */
  minPercent?: number;
  /** Maximum width as percentage of viewport (0-1) */
  maxPercent?: number;
  /** Absolute minimum width in pixels */
  minPixels?: number;
  /** Absolute maximum width in pixels */
  maxPixels?: number;
  /** Direction of resize: 'left' (panel on right, drag left to increase) or 'right' (panel on left, drag right to increase) */
  direction?: 'left' | 'right';
}

interface UseResizablePanelReturn {
  /** Current panel width in pixels */
  width: number;
  /** Whether panel is currently being resized */
  isResizing: boolean;
  /** Handler for mousedown on resize handle */
  handleMouseDown: (e: React.MouseEvent) => void;
}

export function useResizablePanel({
  storageKey,
  defaultWidth,
  minPercent = 0.2,
  maxPercent = 0.4,
  minPixels = 300,
  maxPixels = 600,
  direction = 'right',
}: UseResizablePanelOptions): UseResizablePanelReturn {
  const [width, setWidth] = useState(() => {
    const saved = localStorage.getItem(storageKey);
    return saved ? parseInt(saved, 10) : defaultWidth;
  });
  const [isResizing, setIsResizing] = useState(false);
  const startXRef = useRef<number>(0);
  const startWidthRef = useRef<number>(0);
  // Track current width in a ref to avoid stale closure in mouseup handler
  const widthRef = useRef<number>(width);

  // Keep widthRef in sync with width state
  useEffect(() => {
    widthRef.current = width;
  }, [width]);

  useEffect(() => {
    if (!isResizing) return;

    const handleMouseMove = (e: MouseEvent) => {
      // For panels on the right, dragging left (negative deltaX) increases width
      // For panels on the left, dragging right (positive deltaX) increases width
      const deltaX =
        direction === 'left'
          ? startXRef.current - e.clientX
          : e.clientX - startXRef.current;
      const viewportWidth = window.innerWidth;
      const minWidth = Math.max(minPixels, viewportWidth * minPercent);
      const maxWidth = Math.min(maxPixels, viewportWidth * maxPercent);
      const newWidth = Math.max(
        minWidth,
        Math.min(maxWidth, startWidthRef.current + deltaX)
      );
      setWidth(newWidth);
      widthRef.current = newWidth;
    };

    const handleMouseUp = () => {
      setIsResizing(false);
      // Use ref to get current width, avoiding stale closure
      localStorage.setItem(storageKey, widthRef.current.toString());
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);

    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [
    isResizing,
    storageKey,
    minPercent,
    maxPercent,
    minPixels,
    maxPixels,
    direction,
  ]);

  const handleMouseDown = (e: React.MouseEvent) => {
    e.preventDefault();
    startXRef.current = e.clientX;
    startWidthRef.current = width;
    setIsResizing(true);
  };

  return { width, isResizing, handleMouseDown };
}
