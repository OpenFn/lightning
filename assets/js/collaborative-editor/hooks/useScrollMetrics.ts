/**
 * useScrollMetrics - Keeps a scroll container's geometry in state, so anything
 * drawn outside that container can react to where it has been scrolled.
 *
 * Owns the element refs and the listeners, and nothing else: what the numbers
 * are used for is the caller's business. Pair it with `useOverlayScrollbar` to
 * draw a scrollbar beside the container, read `canScrollDown` to show something
 * only while content is still hidden below the fold, or both — either way there
 * is one listener and one set of numbers, so two readers cannot disagree about
 * where the container is scrolled to.
 */

import { useEffect, useState } from 'react';

/**
 * How near the bottom counts as being at it. scrollTop is fractional, and at a
 * true full scroll it routinely lands a fraction of a pixel short of the sum —
 * more so under browser zoom. Testing for an exact match leaves anything keyed
 * to "there is more below" faintly on forever.
 */
const SCROLL_END_TOLERANCE = 1;

export interface ScrollMetrics {
  scrollTop: number;
  scrollHeight: number;
  clientHeight: number;
}

interface UseScrollMetricsReturn {
  /** Attach to the scrolling element. */
  scrollRef: (el: HTMLDivElement | null) => void;
  /**
   * Attach to a single wrapper around everything inside the scrolling element.
   * Watching one stable wrapper rather than the children means a swap between,
   * say, a loading message and the loaded list is still noticed.
   */
  contentRef: (el: HTMLDivElement | null) => void;
  /** The scrolling element, for consumers that need to scroll it. */
  element: HTMLDivElement | null;
  /** Null until the element exists. */
  metrics: ScrollMetrics | null;
  /**
   * Whether there is content past the bottom edge. False both at a full scroll
   * and when the content was never tall enough to scroll.
   */
  canScrollDown: boolean;
}

export function useScrollMetrics(): UseScrollMetricsReturn {
  // Callback refs rather than useRef, because a scroll container inside a
  // dialog only exists once the dialog opens. A ref object is filled in without
  // re-rendering and without re-running any effect, so the measuring effect
  // would run once at mount — finding nothing — and never again.
  const [element, setElement] = useState<HTMLDivElement | null>(null);
  const [contentEl, setContentEl] = useState<HTMLDivElement | null>(null);
  const [metrics, setMetrics] = useState<ScrollMetrics | null>(null);

  useEffect(() => {
    if (!element) {
      setMetrics(null);
      return;
    }

    const measure = () => {
      const { scrollTop, scrollHeight, clientHeight } = element;
      // Same numbers, same object: a resize that changed nothing should not
      // re-render everything reading this.
      setMetrics(previous =>
        previous &&
        previous.scrollTop === scrollTop &&
        previous.scrollHeight === scrollHeight &&
        previous.clientHeight === clientHeight
          ? previous
          : { scrollTop, scrollHeight, clientHeight }
      );
    };

    measure();
    element.addEventListener('scroll', measure, { passive: true });

    // The container resizing and the content growing or shrinking are both
    // reasons to re-measure, and neither fires a scroll event — filtering a
    // list down changes scrollHeight while scrollTop stands still.
    //
    // The disable below is for browserslist's "defaults" still including KaiOS
    // 2.5. The editor has never run there, and the diagram relies on
    // ResizeObserver too.
    // eslint-disable-next-line compat/compat
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    if (contentEl) observer.observe(contentEl);

    return () => {
      element.removeEventListener('scroll', measure);
      observer.disconnect();
    };
  }, [element, contentEl]);

  const canScrollDown = metrics
    ? metrics.scrollHeight - metrics.clientHeight - metrics.scrollTop >
      SCROLL_END_TOLERANCE
    : false;

  return {
    scrollRef: setElement,
    contentRef: setContentEl,
    element,
    metrics,
    canScrollDown,
  };
}
