import invariant from 'tiny-invariant';
import warning from 'tiny-warning';

import ReactDOMClient from 'react-dom/client';

import {
  getClosestReactContainerElement,
  importComponent,
  isReactContainerElement,
  isReactHookedElement,
  lazyLoadComponent,
  renderSlots,
  replaceEqualDeep,
  withProps,
} from '#/react/lib';

import { Boundary } from '#/react/components';

import type { ReactComponentHook } from '#/react/types';
import { StrictMode } from 'react';
import type { ViewHook } from 'phoenix_live_view';

export const ReactComponent = {
  mounted() {
    invariant(
      isReactHookedElement(this.el),
      this.errorMsg('Element is not valid for this hook!')
    );
    invariant(
      isReactContainerElement(this.el.nextElementSibling) &&
        this.el.nextElementSibling.dataset.reactContainer === this.el.id,
      this.errorMsg(`Missing valid React container element!`)
    );

    this.onBoundary = this.onBoundary.bind(this);
    this.subscribe = this.subscribe.bind(this);
    this.getProps = this.getProps.bind(this);
    this.getPortals = this.getPortals.bind(this);
    this.portals = new Map();

    this.liveSocket.owner(this.el, view => {
      this.view = view;
    });
    this.name = this.el.dataset.reactName;
    this.file = this.el.dataset.reactFile;
    this.containerEl = this.el.nextElementSibling;
    this.Component = withProps(
      lazyLoadComponent(() => importComponent(this.file, this.name), this.name),
      /* eslint-disable @typescript-eslint/unbound-method -- bound using `Function.prototype.bind` */
      this.subscribe,
      this.getProps,
      this.getPortals,
      /* eslint-enable */
      this.view,
      this.view.componentID(this.el)
    );
    this.listeners = new Set();
    this.boundaryMounted = false;
    this.mount();
  },

  updated() {
    this.setProps();
  },

  beforeDestroy() {
    this.unmount();
  },

  destroyed() {
    window.addEventListener(
      'phx:page-loading-stop',
      () => {
        this.unmount();
      },
      {
        once: true,
      }
    );
  },

  subscribe(onPropsChange: () => void): () => void {
    this.listeners.add(onPropsChange);

    const unsubscribe = () => {
      this.listeners.delete(onPropsChange);
    };

    return unsubscribe;
  },

  getProps() {
    invariant(this.props !== undefined, this.errorMsg('Uninitialized props!'));

    return this.props;
  },

  addPortal(
    children: React.ReactNode,
    container: Element | DocumentFragment,
    key: string
  ) {
    warning(
      !this.portals.has(key),
      this.errorMsg('Portal has already been added! Overwriting!')
    );

    // Immutably update the map
    // See https://zustand.docs.pmnd.rs/guides/maps-and-sets-usage#map-and-set-usage
    this.portals = new Map(this.portals).set(key, [container, children]);

    this.rerender();
  },

  removePortal(key: string) {
    warning(
      this.portals.has(key),
      this.errorMsg('Cannot remove missing portal!')
    );

    // Immutably update the map
    // See https://zustand.docs.pmnd.rs/guides/maps-and-sets-usage#map-and-set-usage
    this.portals = new Map(this.portals);
    this.portals.delete(key);

    this.rerender();
  },

  getPortals() {
    return this.portals;
  },

  onBoundary(element: HTMLDivElement | null) {
    this.view.liveSocket.requestDOMUpdate(() => {
      if (element == null || !element.isConnected || this.boundaryMounted) {
        return;
      }
      this.view.execNewMounted();
      this.boundaryMounted = true;
    });
  },

  setProps() {
    invariant(
      this.el.textContent != null && this.el.textContent !== '',
      this.errorMsg('No content in <script> tag!')
    );

    const props = renderSlots({
      // TODO: Wrap `JSON.parse` in a try/catch, or just let it throw?
      // If the JSON is malformed, it'll throw a [`SyntaxError`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Errors/JSON_bad_parse)
      props: JSON.parse(this.el.textContent) as object,
      view: this.view,
      cID: this.view.componentID(this.el),
    });

    invariant(
      typeof props === 'object',
      this.errorMsg(
        'Invalid `props` type! It should either be an object or `null`.'
      )
    );

    // Using `replaceEqualDeep` means that only values that have changed will be
    // updated. This allows e.g. React [memo](https://react.dev/reference/react/memo)
    // to work correctly.
    // TODO: use [https://github.com/Miserlou/live_json](live_json) instead?
    // https://github.com/woutdp/live_svelte/blob/master/README.md#live_json
    this.props = replaceEqualDeep(this.props, props);

    this.rerender();
  },

  rerender() {
    for (const listener of this.listeners) {
      listener();
    }
  },

  mount() {
    const reactContainerElement = getClosestReactContainerElement(
      this.el,
      this.view.root.el
    );

    if (reactContainerElement == null) {
      this.mountRoot();
    } else {
      const reactContainerHookedElement =
        reactContainerElement.previousElementSibling;

      invariant(
        isReactContainerElement(reactContainerElement) &&
          reactContainerHookedElement instanceof HTMLElement &&
          reactContainerHookedElement.id ===
            reactContainerElement.dataset.reactContainer,
        this.errorMsg(
          `Missing React container element's sibling <script> element!`
        )
      );

      this.liveSocket.owner(reactContainerHookedElement, view => {
        this.containerComponentHook = (() => {
          const hook = view.getHook(reactContainerHookedElement);

          if (
            hook == null ||
            reactContainerHookedElement.dataset['phxHook'] !==
              this.el.dataset['phxHook']
          ) {
            invariant(false);
          }

          return hook as unknown as ReactComponentHook;
        })();

        this.mountPortal();
      });
    }
  },

  getKey(): string {
    // Access the `ViewHook` class so we can access its static methods
    const ViewHook = (Object.getPrototypeOf(this) as ViewHook).constructor;

    // This is guaranteed to give us a unique ID because it's incremented for
    // every `ViewHook` created and never decremented or reset (even across
    // different LiveViews, since they all import the same `ViewHook` module,
    // and it's only instantiated once).
    // See `deps/phoenix_live_view/assets/js/phoenix_live_view/view_hook.js`
    // for its implementation.
    const viewHookId = ViewHook.elementID(this.el);

    // Nevertheless, also incorporate the LiveView's id for good measure, can't hurt
    const key = `${this.view.id}-${String(viewHookId)}`;

    return key;
  },

  mountRoot() {
    invariant(this.root == null, this.errorMsg('React root already created!'));

    this.root = ReactDOMClient.createRoot(this.containerEl, {
      identifierPrefix: this.getKey(),
      // TODO: [error handling](https://18.react.dev/reference/react-dom/client/createRoot#displaying-a-dialog-for-recoverable-errors)?
      onRecoverableError: (error, errorInfo) => {
        console.error(
          'Recoverable error',
          error,
          error instanceof Error && 'cause' in error ? error.cause : undefined,
          errorInfo.componentStack
        );
      },
    });

    this.setProps();

    // We'll only call `render` this once because updates are triggered using
    // `useSyncExternalStore`, and so we don't need to manually trigger re-renders.
    this.root.render(
      // Find common bugs early in development with [`StrictMode`](https://react.dev/reference/react/StrictMode)
      <StrictMode>
        <Boundary
          ref={
            // eslint-disable-next-line @typescript-eslint/unbound-method -- bound using `Function.prototype.bind`
            this.onBoundary
          }
        >
          <this.Component />
        </Boundary>
      </StrictMode>
    );
  },

  mountPortal() {
    invariant(
      this.containerComponentHook != null,
      this.errorMsg('No container React component ViewHook instance!')
    );

    this.setProps();

    this.containerComponentHook.addPortal(
      <Boundary
        ref={
          // eslint-disable-next-line @typescript-eslint/unbound-method -- bound using `Function.prototype.bind`
          this.onBoundary
        }
      >
        <this.Component />
      </Boundary>,
      this.containerEl,
      this.getKey()
    );
  },

  unmount() {
    invariant(
      this.root || this.containerComponentHook,
      this.errorMsg('No React root or portal to unmount!')
    );

    if (this.root) {
      this.unmountRoot();
    } else if (this.containerComponentHook) {
      this.unmountPortal();
    }
  },

  unmountRoot() {
    invariant(this.root != null, this.errorMsg('No React root to unmount!'));
    this.root.unmount();
  },

  unmountPortal() {
    invariant(
      this.containerComponentHook != null,
      this.errorMsg('No container React component ViewHook instance!')
    );

    this.containerComponentHook.removePortal(this.getKey());
  },

  errorMsg(str: string): string {
    return (
      str +
      '\n' +
      'In `ReactComponent` hook with ' +
      [
        // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
        this.name != null &&
          // prettier-ignore -- the above supression should not leak down
          `name \`${this.name}\``,
        `id \`${this.el.id}\``,
      ]
        .filter(Boolean)
        .join(' and ') +
      '.'
    );
  },
} as ReactComponentHook;
