import invariant from 'tiny-invariant';

import type { ReactContainerElement } from '#/react/types';

import { isReactContainerElement } from './is-react-container-element';

/** Try to find an existing React container in DOM ancestry */
export const getClosestReactContainerElement = (
  fromEl: HTMLElement,
  /** Search up to this element */
  toEl?: HTMLElement | null
): ReactContainerElement | null => {
  const el = fromEl.closest<ReactContainerElement>('[data-react-container]');

  if (el == null) return el;

  invariant(isReactContainerElement(el));

  if (toEl == null) {
    return el;
  }

  if (!toEl.contains(el)) {
    return null;
  }

  return el;
};
