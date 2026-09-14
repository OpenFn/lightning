/**
 * useOverlayScrollbar - Turns a scroll container's geometry into a scrollbar
 * drawn beside the container rather than inside it.
 *
 * A native scrollbar takes its width out of the container's content box, so
 * whatever sits in that container gets narrower by an amount the platform
 * decides — around 15px where scrollbars are classic, zero where they overlay,
 * and zero again anywhere once the content is too short to scroll. Any layout
 * that lines that content up against something else therefore shifts depending
 * on the machine it is viewed on, and on whether the list happens to be long
 * that day. Hiding the native bar and drawing one from measurements costs the
 * layout nothing, so the geometry stops depending on it.
 *
 * Takes its numbers from `useScrollMetrics`. The caller owns the thumb's
 * appearance and where it sits; this only says how tall it should be and how
 * far down. Pair it with a container that hides its own scrollbar —
 * `no-scrollbar` in this codebase — or there will be two.
 */

import { useCallback, useMemo } from 'react';

import type { ScrollMetrics } from './useScrollMetrics';

/** Short enough to stay proportional, long enough to stay grabbable. */
const MIN_THUMB_HEIGHT = 24;

export interface ScrollThumb {
  /** Offset from the top of the track, in pixels. */
  top: number;
  /** Thumb length, in pixels. */
  height: number;
}

interface UseOverlayScrollbarReturn {
  /** Where to draw the thumb, or null while there is nothing to scroll. */
  thumb: ScrollThumb | null;
  /** Attach to the thumb's `onPointerDown` to make it draggable. */
  handleThumbPointerDown: (event: React.PointerEvent<HTMLElement>) => void;
}

/**
 * Where the thumb goes for a given geometry, or null when there is nothing to
 * scroll — which is also when a scrollbar should not be showing. Exported for
 * tests: it is the whole of the arithmetic and it touches no DOM.
 */
export function thumbFor(metrics: ScrollMetrics | null): ScrollThumb | null {
  if (!metrics) return null;
  const { scrollTop, scrollHeight, clientHeight } = metrics;
  const scrollable = scrollHeight - clientHeight;
  if (scrollable <= 0) return null;

  // Never longer than the track it runs in, which the minimum would otherwise
  // allow for a container shorter than MIN_THUMB_HEIGHT.
  const height = Math.min(
    Math.max((clientHeight / scrollHeight) * clientHeight, MIN_THUMB_HEIGHT),
    clientHeight
  );
  // Scaled against the travel rather than the track, so a thumb held at its
  // minimum height still lands flush with the bottom at full scroll.
  const travel = clientHeight - height;
  // Clamped because a rubber-band bounce can report a scrollTop past either
  // end, and the thumb would ride out of its track for the length of it.
  const progress = Math.min(Math.max(scrollTop / scrollable, 0), 1);
  return { top: progress * travel, height };
}

export function useOverlayScrollbar(
  element: HTMLElement | null,
  metrics: ScrollMetrics | null
): UseOverlayScrollbarReturn {
  const thumb = useMemo(() => thumbFor(metrics), [metrics]);

  // Dragging has to be wired up by hand, since the browser only does it for a
  // scrollbar it painted itself. Pointer capture keeps the drag alive once the
  // pointer leaves the thumb, which it will.
  const handleThumbPointerDown = useCallback(
    (event: React.PointerEvent<HTMLElement>) => {
      if (!element || !metrics || !thumb) return;
      event.preventDefault();

      const travel = metrics.clientHeight - thumb.height;
      if (travel <= 0) return;

      const startY = event.clientY;
      const startScrollTop = metrics.scrollTop;
      const scrollable = metrics.scrollHeight - metrics.clientHeight;
      const handle = event.currentTarget;
      handle.setPointerCapture(event.pointerId);

      const onMove = (moved: PointerEvent) => {
        element.scrollTop =
          startScrollTop + ((moved.clientY - startY) / travel) * scrollable;
      };
      const onRelease = () => {
        handle.removeEventListener('pointermove', onMove);
        handle.removeEventListener('pointerup', onRelease);
        handle.removeEventListener('pointercancel', onRelease);
      };

      handle.addEventListener('pointermove', onMove);
      handle.addEventListener('pointerup', onRelease);
      handle.addEventListener('pointercancel', onRelease);
    },
    [element, metrics, thumb]
  );

  return { thumb, handleThumbPointerDown };
}
