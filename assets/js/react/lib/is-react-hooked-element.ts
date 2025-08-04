import type { ReactHookedElement } from '#/react/types';

export const isReactHookedElement = (
  el: Element | null
): el is ReactHookedElement =>
  el instanceof HTMLElement &&
  el.dataset['reactName'] !== undefined &&
  el.dataset['reactFile'] !== undefined;
