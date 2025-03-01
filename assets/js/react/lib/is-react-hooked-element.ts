import type { ReactHookedElement } from '#/react/types';

export const isReactHookedElement = (
  el: Element | null
): el is ReactHookedElement =>
  el instanceof HTMLScriptElement &&
  el.dataset['reactName'] !== undefined &&
  el.dataset['reactFile'] !== undefined &&
  Boolean(
    Array.from(el.attributes).find(
      attr => attr.name === 'phx-hook' && attr.value === 'ReactComponent'
    )
  );
