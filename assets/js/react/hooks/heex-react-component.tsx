import type { ViewHook } from 'phoenix_live_view';
import { StrictMode } from 'react';
import ReactDOMClient from 'react-dom/client';
import invariant from 'tiny-invariant';
import warning from 'tiny-warning';

import type { GetPhoenixHookInternalThis } from '#/hooks/PhoenixHook';
import { Boundary } from '#/react/components';
import {
  importComponent,
  isReactContainerElement,
  isReactHookedElement,
  lazyLoadComponent,
  replaceEqualDeep,
  withProps,
  RootObserver,
} from '#/react/lib';
import type { ReactComponentHook } from '#/react/types';

const rootObserver = new RootObserver();

export const HeexReactComponent = {
  mounted() {
    this._name = this.el.dataset.reactName;
    this._file = this.el.dataset.reactFile;

    const id = this.el.dataset.reactId;
    if (id != null) {
      this._id = id;
    }

    const portalTarget = this.el.dataset.reactPortalTarget;
    if (portalTarget != null) {
      this._portalTarget = portalTarget;
    }

    this._onBoundary = this._onBoundary.bind(this);
    this._subscribe = this._subscribe.bind(this);
    this._getProps = this._getProps.bind(this);
    this._getPortals = this._getPortals.bind(this);
    this._beforeUnmountCallbacks = new Set();
    this._portals = new Map();
    this._listeners = new Set();
    this._boundaryMounted = false;

    invariant(
      isReactHookedElement(this.el),
      this._errorMsg('Element is not valid for this hook!')
    );

    invariant(
      isReactContainerElement(this.el.nextElementSibling) &&
        this.el.nextElementSibling.dataset.reactContainer === this.el.id,
      this._errorMsg(`Missing valid React container element!`)
    );

    this._containerEl = this.el.nextElementSibling;
    this._Component = withProps(
      lazyLoadComponent(
        () => importComponent(this._file, this._name),
        this._name
      ),
      /* eslint-disable @typescript-eslint/unbound-method -- bound using `Function.prototype.bind` */
      this._subscribe,
      this._getProps,
      this._getPortals,
      {
        pushEvent: this.pushEvent.bind(this),
        handleEvent: (name, callback) => {
          const ref = this.handleEvent(name, callback);
          return () => {
            this.removeHandleEvent(ref);
          };
        },
        pushEventTo: this.pushEventTo.bind(this, this.el),
        el: this.el,
        containerEl: this._containerEl,
        navigate: path => {
          this.liveSocket.execJS(
            this.el,
            '[["patch",{"replace":false,"href":"' + path + '"}]]'
          );
        },
      },
      /* eslint-enable */
      this.__view(),
      this.__view().componentID(this.el)
    );

    this._mount();
  },

  updated() {
    this._setProps();
  },

  beforeDestroy() {
    this._unmount();
  },

  destroyed() {
    window.addEventListener(
      'phx:page-loading-stop',
      () => {
        this._unmount();
      },
      {
        once: true,
      }
    );
  },

  _subscribe(onPropsChange) {
    this._listeners.add(onPropsChange);

    const unsubscribe = () => {
      this._listeners.delete(onPropsChange);
    };

    return unsubscribe;
  },

  _getProps() {
    invariant(
      this._props !== undefined,
      this._errorMsg('Uninitialized props!')
    );
    return this._props;
  },

  addPortal(render, container, key) {
    warning(
      !this._portals.has(key),
      this._errorMsg('Portal has already been added! Overwriting!')
    );

    // Immutably update the map
    // See https://zustand.docs.pmnd.rs/guides/maps-and-sets-usage#map-and-set-usage
    this._portals = new Map(this._portals).set(key, [container, render]);

    this._rerender();
  },

  removePortal(key) {
    warning(
      this._portals.has(key),
      this._errorMsg('Cannot remove missing portal!')
    );

    // Immutably update the map
    // See https://zustand.docs.pmnd.rs/guides/maps-and-sets-usage#map-and-set-usage
    this._portals = new Map(this._portals);
    this._portals.delete(key);

    this._rerender();
  },

  _getPortals() {
    return this._portals;
  },

  _onBoundary(element) {
    this.__view().liveSocket.requestDOMUpdate(() => {
      if (element == null) return;

      this.__view().execNewMounted();
      this._boundaryMounted = true;

      if (this._id != null) {
        const beforeUnmount = rootObserver.mounted(
          this._id,
          this as unknown as ReactComponentHook
        );

        this._onBeforeUnmount(beforeUnmount);
      }
    });
  },

  _setProps() {
    invariant(
      this.el.textContent != null && this.el.textContent !== '',
      this._errorMsg('No content in <script> tag!')
    );

    // TODO: Wrap `JSON.parse` in a try/catch, or just let it throw?
    // If the JSON is malformed, it'll throw a [`SyntaxError`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Errors/JSON_bad_parse)
    const props = JSON.parse(this.el.textContent) as object;

    invariant(
      typeof props === 'object',
      this._errorMsg(
        'Invalid `props` type! It should either be an object or `null`.'
      )
    );

    // Using `replaceEqualDeep` means that only values that have changed will be
    // updated. This allows e.g. React [memo](https://react.dev/reference/react/memo)
    // to work correctly.
    // TODO: use [https://github.com/Miserlou/live_json](live_json) instead?
    // https://github.com/woutdp/live_svelte/blob/master/README.md#live_json
    this._props = replaceEqualDeep(this._props, props);

    this._rerender();
  },

  _rerender() {
    for (const listener of this._listeners) {
      listener();
    }
  },

  _mount() {
    if (this._portalTarget == null) {
      this._mountRoot();
    } else {
      this._mountPortal();
    }
  },

  _onBeforeUnmount(callback) {
    this._beforeUnmountCallbacks.add(callback);
  },

  _beforeUnmount() {
    for (const callback of this._beforeUnmountCallbacks) {
      callback();
    }
    this._beforeUnmountCallbacks.clear();
  },

  _getKey() {
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
    const key = `${this.__view().id}-${String(viewHookId)}`;

    return key;
  },

  _mountRoot() {
    invariant(
      this._root == null,
      this._errorMsg('React root already created!')
    );

    this._root = ReactDOMClient.createRoot(this._containerEl, {
      identifierPrefix: this._getKey(),
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

    this._setProps();

    // We'll only call `render` this once because updates are triggered using
    // `useSyncExternalStore`, and so we don't need to manually trigger re-renders.
    this._root.render(
      // Find common bugs early in development with [`StrictMode`](https://react.dev/reference/react/StrictMode)
      <StrictMode>
        <Boundary
          ref={
            // eslint-disable-next-line @typescript-eslint/unbound-method -- bound using `Function.prototype.bind`
            this._onBoundary
          }
        >
          <this._Component />
        </Boundary>
      </StrictMode>
    );
  },

  _mountPortal() {
    invariant(this._portalTarget != null, this._errorMsg('No `portalTarget`!'));

    this._setProps();

    // If the target is already mounted our callback will be called right away
    const unsubscribe = rootObserver.subscribe(this._portalTarget, message => {
      switch (message.type) {
        case 'mounted': {
          this._portalHook = message.hook;
          this._portalHook.addPortal(
            () => (
              <Boundary
                ref={
                  // eslint-disable-next-line @typescript-eslint/unbound-method -- bound using `Function.prototype.bind`
                  this._onBoundary
                }
              >
                <this._Component />
              </Boundary>
            ),
            this._containerEl,
            this._getKey()
          );
          break;
        }

        case 'beforeUnmount': {
          this._unmount();
          break;
        }

        default: {
          message satisfies never;
          invariant(message, 'Unhandled React root observer message!');
        }
      }
    });

    this._onBeforeUnmount(unsubscribe);
  },

  _unmount() {
    invariant(
      this._root != null || this._portalHook != null,
      this._errorMsg('No React root or portal to unmount!')
    );

    this._beforeUnmount();

    if (this._root) {
      this._unmountRoot();
    } else if (this._portalHook) {
      this._unmountPortal();
    }
  },

  _unmountRoot() {
    invariant(this._root != null, this._errorMsg('No React root to unmount!'));
    this._root.unmount();
  },

  _unmountPortal() {
    invariant(
      this._portalHook != null,
      this._errorMsg('No container React component ViewHook instance!')
    );

    this._portalHook.removePortal(this._getKey());
  },

  _errorMsg(str) {
    return (
      str +
      '\n' +
      'In `ReactComponent` hook with ' +
      [
        this._name != null &&
          // prettier-ignore -- the above supression should not leak down
          `name \`${this._name}\``,
        `id \`${this.el.id}\``,
      ]
        .filter(Boolean)
        .join(' and ') +
      '.'
    );
  },

  /*
   * Because of the way Phoenix LiveView typed their hooks we need to make
   * type it like this, this allows us to use the "internal" typedef for the
   * definition but will not expose the "internal" methods and properties
   * (those starting with `_`).
   */
} as GetPhoenixHookInternalThis<ReactComponentHook> as unknown as ReactComponentHook;
