import type { ReactContainerElement } from '#/react/types';

export const isReactContainerElement = (
  el: Element | null
): el is ReactContainerElement =>
  el instanceof HTMLElement &&
  el.dataset['reactContainer'] !== undefined &&
  Boolean(
    Array.from(el.attributes).find(
      attr => attr.name === 'phx-update' && attr.value === 'ignore'
    )
  );
