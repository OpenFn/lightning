import invariant from 'tiny-invariant';
import warning from 'tiny-warning';

import ReactDOM from 'react-dom';
import ReactDOMClient from 'react-dom/client';
import * as ReactIs from 'react-is';

import {
  getClosestReactContainerElement,
  importComponent,
  isReactContainerElement,
  isReactHookedElement,
  lazyLoadComponent,
  mergeChildren,
  renderSlots,
  replaceEqualDeep,
  withProps,
} from '#/react/lib';

import { Boundary } from '#/react/components';

import type { ReactComponentHook } from '#/react/types';

/**
 * TODO: How to correctly run phoenix lifecycle events for child components, i.e. the ones that React is interleaving?
 * e.g. we need any ViewHook to correctly run (but we're not just concerned with ViewHooks)
 *
 * - [WONTFIX](https://github.com/phoenixframework/phoenix_live_view/issues/2563)
 * - method `performPatch` in
     `deps/phoenix_live_view/assets/js/phoenix_live_view/view.js` seems to
     contain the logic that glues DOM elements to ViewHooks.
 */

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

    this.liveSocket.owner(this.el, view => {
      this.view = view;
    });
    this.name = this.el.dataset.reactName;
    this.file = this.el.dataset.reactFile;
    this.containerEl = this.el.nextElementSibling;
    this.Component = withProps(
      lazyLoadComponent(() => importComponent(this.file, this.name), this.name),
      this.subscribe.bind(this),
      this.getProps.bind(this)
    );
    this.listeners = new Set();
    this.slots = new Map();
    this.mount();
  },

  beforeUpdate() {
    this.setProps();
  },

  beforeDestroy() {
    this.unmount();
  },

  destroyed() {
    window.addEventListener('phx:page-loading-stop', () => this.unmount(), {
      once: true,
    });
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

  addChild(child) {
    warning(
      this.children == null || !this.children.has(child),
      'Child has already been added!'
    );
    this.children ??= new Set();
    this.children.add(child);

    this.setProps();
  },

  removeChild(child) {
    warning(
      this.children != null && this.children.has(child),
      'Cannot remove missing child!'
    );
    this.children?.delete(child);

    if (this.children != null && this.children.size === 0) {
      this.children = null;
    }

    this.setProps();
  },

  setProps() {
    invariant(
      this.el.textContent != null && this.el.textContent !== '',
      this.errorMsg('No content in <script> tag!')
    );

    const props = renderSlots({
      // TODO: Wrap `JSON.parse` in a try/catch, or just let it throw?
      // If the JSON is malformed, it'll throw a [`SyntaxError`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Errors/JSON_bad_parse)
      props: JSON.parse(this.el.textContent),
      view: this.view,
      slots: this.slots,
    });

    invariant(
      typeof props === 'object',
      this.errorMsg(
        'Invalid `props` type! It should either be an object or `null`.'
      )
    );

    const propsChildren =
      props === null || !('children' in props) ? null : props.children;

    invariant(
      propsChildren === null || ReactIs.isElement(propsChildren),
      this.errorMsg('Invalid `props.children` type!')
    );

    const children = mergeChildren(
      propsChildren,
      this.children != null ? Array.from(this.children) : this.children
    );

    // Using `replaceEqualDeep` means that only values that have changed will be
    // updated. This allows e.g. React [memo](https://react.dev/reference/react/memo)
    // to work correctly.
    // TODO: use [https://github.com/Miserlou/live_json](live_json) instead?
    // https://github.com/woutdp/live_svelte/blob/master/README.md#live_json
    this.props = replaceEqualDeep(this.props, {
      ...props,
      ...(children != null && { children }),
    });

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
          reactContainerHookedElement instanceof HTMLScriptElement &&
          reactContainerHookedElement.type === 'application/json' &&
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
            return null;
          }

          return hook as ReactComponentHook;
        })();

        this.mountPortal();
      });
    }
  },

  getKey(): string {
    // Access the `ViewHook` class so we can access its static methods
    const ViewHook = Object.getPrototypeOf(this).constructor;

    // This is guaranteed to give us a unique id because it's incremented for
    // every `ViewHook` created and never decremented or reset (even across
    // different LiveViews, since they all import the same `ViewHook` module,
    // and it's only instantiated once).
    // See `deps/phoenix_live_view/assets/js/phoenix_live_view/view_hook.js`
    // for its implementation.
    const viewHookId: number = ViewHook.elementID(this.el);

    // Nevertheless, also incorporate the LiveView's id for good measure, can't hurt
    const key = `${this.view.id}-${viewHookId}`;

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
      <Boundary>
        <this.Component />
      </Boundary>
    );
  },

  mountPortal() {
    invariant(
      this.portal == null,
      this.errorMsg('React portal already created!')
    );

    invariant(
      this.containerComponentHook != null,
      this.errorMsg('No container React component ViewHook instance!')
    );

    this.setProps();

    this.portal = ReactDOM.createPortal(
      <this.Component />,
      this.containerEl,
      this.getKey()
    );

    this.containerComponentHook.addChild(this.portal);
  },

  unmount() {
    invariant(
      this.root || this.portal,
      this.errorMsg('No React root or portal to unmount!')
    );

    if (this.root) {
      this.unmountRoot();
    } else if (this.portal) {
      this.unmountPortal();
    }
  },

  unmountRoot() {
    invariant(this.root != null, this.errorMsg('No React root to unmount!'));
    this.root.unmount();
  },

  unmountPortal() {
    invariant(
      this.portal != null,
      this.errorMsg('No React portal to unmount!')
    );

    invariant(
      this.containerComponentHook != null,
      this.errorMsg('No container React component ViewHook instance!')
    );

    this.containerComponentHook.removeChild(this.portal);
  },

  errorMsg(str: string): string {
    return (
      str +
      '\n' +
      'In `ReactComponent` hook with ' +
      [this.name != null && `name \`${this.name}\``, `id \`${this.el.id}\``]
        .filter(Boolean)
        .join(' and ') +
      '.'
    );
  },
} as ReactComponentHook;
