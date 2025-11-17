import type { View } from 'phoenix_live_view';
import _DOMPatch from 'phoenix_live_view/dom_patch';

interface DOMPatch {
  // eslint-disable-next-line @typescript-eslint/no-misused-new
  new (
    view: View,
    el: HTMLElement,
    id: string,
    html: string,
    streams: Set<unknown>,
    targetCID?: number | null
  ): DOMPatch;
  after(
    kind: 'transitionsDiscarded',
    callback: (els: HTMLElement[]) => void
  ): void;
  after(kind: string, callback: (el: HTMLElement) => void): void;
  before(
    kind: string,
    callback: (fromEl: HTMLElement, toEl: HTMLElement) => void
  ): void;
  perform(isJoinPatch?: boolean): boolean | undefined;
}

const DOMPatch = _DOMPatch as unknown as DOMPatch;

/**
 * We need to trigger Phoenix lifecycle events for child components, i.e. the
 * ones that React is rendering. I.e. we need child ViewHooks to correctly run
 *
 * - [WONTFIX](https://github.com/phoenixframework/phoenix_live_view/issues/2563)
 * - based on `performPatch` in `deps/phoenix_live_view/assets/js/phoenix_live_view/view.js`
 */
export const performPatch = (
  view: View,
  el: HTMLElement,
  html: string,
  targetCID: number | null = null
) => {
  const patch = new DOMPatch(view, el, view.id, html, new Set(), targetCID);

  const removedEls = new Array<HTMLElement>();
  let phxChildrenAdded: boolean | undefined = false;
  const updatedHookIds = new Set();

  patch.after('added', el => {
    view.liveSocket.triggerDOM('onNodeAdded', [el]);
    view.maybeAddNewHook(el);
    // @ts-expect-error -- this was in the OG `DOMPatch`

    if (el.getAttribute) {
      view.maybeMounted(el);
    }
  });

  patch.after('phxChildAdded', el => {
    if (el.getAttribute && el.getAttribute('data-phx-sticky') !== null) {
      view.liveSocket.joinRootViews();
    } else {
      phxChildrenAdded = true;
    }
  });

  patch.before('updated', (fromEl, toEl) => {
    const hook = view.triggerBeforeUpdateHook(fromEl, toEl);
    if (hook) {
      updatedHookIds.add(fromEl.id);
    }
  });

  patch.after('updated', el => {
    if (updatedHookIds.has(el.id)) {
      view.getHook(el)?.__updated();
    }
  });

  patch.after('discarded', el => {
    if (el.nodeType === Node.ELEMENT_NODE) {
      removedEls.push(el);
    }
  });

  patch.after('transitionsDiscarded', els => {
    view.afterElementsRemoved(els, true);
  });

  phxChildrenAdded ||= patch.perform();

  view.afterElementsRemoved(removedEls, true);

  if (phxChildrenAdded) {
    view.joinNewChildren();
  }
};
